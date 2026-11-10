--[[
vlc-autofolder: a Lua interface script for VLC 3.0.x.

VLC starts it with the extra-interface setting:
    extraintf=luaintf{intf=autofolder}

Skeleton for now (To do 1): it logs that it started, then waits until VLC
closes. The folder logic comes in To do 2.
--]]

local POLL_US = 300000 -- 300 ms, in microseconds

vlc.msg.info("[autofolder] started")

-- Never wrap mwait in pcall: when VLC closes, mwait raises "Interrupted.",
-- and that error must end this script, or VLC can hang on close.
while true do
    vlc.misc.mwait(vlc.misc.mdate() + POLL_US)
end
