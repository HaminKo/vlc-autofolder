--[[
Helpers for the test driver scripts (tests\lua\intf\test_*.lua). Load with:
    local t = require "testlib"

A driver is a Lua interface script that tests\run-tests.ps1 starts in a
headless VLC. Its global `config` comes from the lua-config setting:
    config.out    the results file to write
    config.media  the test media folder

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

-- Runs the test body, records an uncaught error as a failure, writes "done"
-- and quits VLC.
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
    vlc.misc.quit()
    if not wrote then
        error(write_err, 0)
    end
end

return M
