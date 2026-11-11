--[[
A large folder (To do 2 step D). run-tests.ps1 starts it next to autofolder,
with the last video by date of the 500-video folder on VLC's command line
(tests\TestCommon.ps1, Initialize-BigFolder), so autofolder adds 499 videos
and moves them all before it. config.list: the folder's names, oldest first.
Expected:
- the playlist is the whole folder in date order within LIMIT_S seconds of
  the file starting (a slow build as a whole);
- meanwhile, and for 2 s after, no playlist call waits longer than
  MAX_WAIT_MS (one long hold of the playlist, by autofolder or VLC's
  preparsing, which would also freeze VLC's window). Each vlc.playlist call
  holds the playlist on its own, so a slow build made of many short calls
  only shows in the first check;
- the file keeps playing and was started once.
The timings go into the results as info lines; "started" is seen within
50 ms (t.wait_for) and the order is checked every 250 ms.
--]]

local t = require "testlib"

local LIMIT_S = 5 -- measured: 0.3 to 0.5 s
local MAX_WAIT_MS = 250 -- measured: at most 3 ms

local function ms(us)
    return string.format("%.0f ms", us / 1000)
end

-- Where the playlist first differs from the names `want`, for the failure message.
local function first_difference(want)
    local items = t.playlist_items()
    for i, name in ipairs(want) do
        local got = items[i] and t.file_name(items[i].path)
        if got ~= name then
            return string.format("%d items; item %d is %s, wanted %s", #items, i, tostring(got), name)
        end
    end
    return string.format("%d items, %d wanted", #items, #want)
end

t.run(function()
    local want = t.read_lines(config.list)
    local order = table.concat(want, " | ")
    local start = vlc.misc.mdate()
    local playing = t.wait_for(t.current_item, 10)
    if not t.check("a file is playing", playing ~= nil, "nothing playing after 10 s") then
        return
    end
    local started = vlc.misc.mdate()
    t.equal("the opened file is the last by date", t.file_name(playing.path), want[#want])

    -- Every 20 ms, how long vlc.playlist.current() waits for the playlist;
    -- every 250 ms, whether the order is reached.
    local longest, done, checked = 0, nil, 0
    local stop = started + LIMIT_S * 1000000
    while vlc.misc.mdate() < stop do
        local before = vlc.misc.mdate()
        vlc.playlist.current()
        longest = math.max(longest, vlc.misc.mdate() - before)
        if not done and before - checked >= 250000 then
            checked = before
            if t.playlist_names() == order then
                done = vlc.misc.mdate()
                stop = done + 2000000
            end
        end
        vlc.misc.mwait(vlc.misc.mdate() + 20000)
    end

    t.info("the file started " .. ms(started - start) .. " after the driver")
    if t.check("the whole folder in date order within " .. LIMIT_S .. " s", done, first_difference(want)) then
        t.info("the folder was in order " .. ms(done - started) .. " after the file started (checked every 250 ms)")
    end
    t.info("longest wait for the playlist: " .. ms(longest))
    t.check("no playlist call waited over " .. MAX_WAIT_MS .. " ms", longest <= MAX_WAIT_MS * 1000, ms(longest))
    t.equal("the opened file still plays", vlc.playlist.current(), playing.id)
    local now = vlc.playlist.get(playing.id)
    t.equal("the opened file was started once", now and now.nb_played, 1)

    -- What autofolder's poll costs with this playlist: one read per poll.
    local before = vlc.misc.mdate()
    for _ = 1, 10 do
        t.playlist_items()
    end
    t.info(string.format("reading the %d-item playlist: %.1f ms each", #t.playlist_items(),
        (vlc.misc.mdate() - before) / 10000))
end)
