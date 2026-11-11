--[[
Smoke test: the test setup itself works.
run-tests.ps1 starts it next to autofolder (chain syntax), with
"Episode 2.mkv" on VLC's command line, like a double-click.
The runner checks VLC's log for autofolder's start line and its clean exit.
--]]

local t = require "testlib" -- also checks that require finds intf\modules

t.run(function()
    -- Isolation: VLC's user folder is the portable folder, not %APPDATA%\vlc.
    local userdir = vlc.config.userdatadir()
    t.info("userdatadir=" .. userdir)
    t.check("userdatadir is the portable folder", userdir:match("[\\/]portable$") ~= nil, userdir)

    local item = t.wait_for(t.current_item, 5)
    if not t.check("a file is playing", item ~= nil, "nothing playing after 5 s") then
        return
    end
    t.info("playing " .. item.path)
    t.check("it is the command-line file", item.path:match("/Episode%%202%.mkv$") ~= nil, item.path)

    -- The generated test video really plays (its time moves on). Opening it took
    -- up to ~8 s on the first run of a day (measured 2026-11-11), so wait.
    local time = t.wait_for(function() return t.input_time() > 0 end, 10)
    t.check("playback time advances", time, "time still 0 after 10 s")
end)
