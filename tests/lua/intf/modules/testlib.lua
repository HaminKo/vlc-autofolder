--[[
Helpers for the test driver scripts (tests\lua\intf\test_*.lua). Load with:
    local t = require "testlib"

A driver is a Lua interface script that tests\run-tests.ps1 starts in a
headless VLC. Its global `config` comes from the lua-config setting:
    config.out     the results file to write
    config.media   the test media folder
    config.videos  a file listing the test videos, oldest first (read_lines)
    config.unc     the media folder as a UNC path (\\localhost\C$\...)

Results file, one line each:
    ok NAME | fail NAME: MESSAGE | info TEXT | done
run-tests.ps1 passes a case only with a "done" line and no "fail" line.
--]]

local M = {}

local out -- the results file, opened on the first write

local function write(line)
    if not out then
        -- On failure vlc.io.open returns no value at all, not nil and a message.
        out = vlc.io.open(config.out, "w")
        if not out then
            error("cannot write the results file " .. tostring(config.out), 0)
        end
    end
    out:write(line .. "\n")
    out:flush()
end

function M.info(text)
    write("info " .. tostring(text))
end

function M.ok(name)
    write("ok " .. name)
end

function M.fail(name, message)
    write("fail " .. name .. ": " .. tostring(message))
end

-- Records ok or fail; returns cond.
function M.check(name, cond, message)
    if cond then
        M.ok(name)
    else
        M.fail(name, message or "condition is false")
    end
    return cond
end

function M.equal(name, actual, expected)
    return M.check(name, actual == expected,
        "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

function M.sleep(seconds)
    vlc.misc.mwait(vlc.misc.mdate() + seconds * 1000000)
end

-- Calls fn every 50 ms until it returns a true value or timeout_s passes.
-- Returns fn's last result.
function M.wait_for(fn, timeout_s)
    local deadline = vlc.misc.mdate() + (timeout_s or 5) * 1000000
    local result = fn()
    while not result and vlc.misc.mdate() < deadline do
        vlc.misc.mwait(vlc.misc.mdate() + 50000)
        result = fn()
    end
    return result
end

-- The playing item (a table with id, name, path, ...), or nil.
function M.current_item()
    local id = vlc.playlist.current()
    if id == -1 then
        return nil
    end
    return vlc.playlist.get(id)
end

-- The playing input's time in microseconds, or 0 when nothing plays.
function M.input_time()
    local input = vlc.object.input()
    return input and vlc.var.get(input, "time") or 0
end

-- The lines of a UTF-8 text file, without the line ends.
function M.read_lines(path)
    local file = vlc.io.open(path, "r")
    if not file then
        error("cannot read " .. tostring(path), 0)
    end
    local text = file:read("*a") or ""
    file:close()
    if text ~= "" and text:sub(-1) ~= "\n" then
        text = text .. "\n" -- keep a last line that has no line end
    end
    local lines = {}
    for line in text:gmatch("([^\r\n]*)\r?\n") do
        lines[#lines + 1] = line
    end
    return lines
end

-- The items of the playlist node, in order (tables with id, name, path, ...).
function M.playlist_items()
    return vlc.playlist.get("playlist").children or {}
end

-- The decoded file name at the end of a URI.
function M.file_name(uri)
    return vlc.strings.decode_uri(uri):match("[^/]*$")
end

-- The playlist as "name | name | ...", names taken from the URIs.
function M.playlist_names()
    local names = {}
    for _, item in ipairs(M.playlist_items()) do
        names[#names + 1] = M.file_name(item.path)
    end
    return table.concat(names, " | ")
end

-- Runs the test body, records an uncaught error as a failure, writes "done"
-- and quits VLC. It never returns: VLC's closing interrupts its last wait,
-- and that "Interrupted." error ends the script (run-tests.ps1 allows it).
function M.run(body)
    local ok, err = pcall(body)
    if not ok and tostring(err):find("Interrupted%.") then
        -- VLC is closing: end at once, as the code rules require. With no
        -- "done" line, run-tests.ps1 reports the case as failed.
        error(err, 0)
    end
    -- Quit even if the results file can't be written; VLC's log then shows
    -- the error, and the runner reports it.
    local wrote, write_err = pcall(function()
        if not ok then
            M.fail("uncaught error", err)
        end
        write("done")
        out:close()
    end)
    if not wrote then
        vlc.msg.err(tostring(write_err))
    end
    -- A quit is lost when it comes before vlc.exe has set its exit handler:
    -- a driver that quit 0.1 s after start left VLC running in 5 of 6 runs
    -- (measured 2026-11-11). So quit again every 0.5 s until VLC closes.
    while true do
        vlc.misc.quit()
        vlc.misc.mwait(vlc.misc.mdate() + 500000)
    end
end

return M
