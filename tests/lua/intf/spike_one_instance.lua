--[[
Driver for tests\spike-one-instance.ps1 (run by hand; not a run-tests.ps1 case).
It runs in the first VLC. Once that VLC plays its file, it writes "info ready",
then records the playlist ("*" marks the playing item) each time it changes,
until the spike script creates the file <config.out>.stop (or 30 s pass).
Then it quits VLC.
--]]

local t = require "testlib"

local function snapshot()
    local current = vlc.playlist.current()
    local parts = {}
    for _, item in ipairs(t.playlist_items()) do
        parts[#parts + 1] = (item.id == current and "*" or "") .. t.file_name(item.path)
    end
    return table.concat(parts, " | ")
end

t.run(function()
    if not t.check("the first VLC plays its file", t.wait_for(t.current_item, 10), "nothing after 10 s") then
        return
    end
    local start = vlc.misc.mdate()
    local function record(text)
        t.info(string.format("playlist +%.1f s: %s", (vlc.misc.mdate() - start) / 1e6, text))
    end
    local last = snapshot()
    record(last)
    t.info("ready")
    local stop = config.out .. ".stop"
    local deadline = start + 30 * 1000000
    while not vlc.net.stat(stop) and vlc.misc.mdate() < deadline do
        t.sleep(0.1)
        local now = snapshot()
        if now ~= last then
            record(now)
            last = now
        end
    end
    t.check("the spike script ended the case", vlc.net.stat(stop) ~= nil, "no stop file after 30 s")
end)
