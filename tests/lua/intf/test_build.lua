--[[
Building the folder (To do 2 steps A and B). run-tests.ps1 starts it next to
autofolder, in one of two ways:
- one test video on VLC's command line, like a double-click;
- no file, and config.user and config.open set: the driver enqueues the
  user's own item config.user (a full path), then opens config.open (a name in
  the media folder) with playlist.add, like a double-click handed to a VLC
  that is already running.
Expected: the playlist becomes the user's item (if any), then every video of
the folder in date order (videos.txt, without names starting with "." other
than the opened one), and the opened file keeps playing. Previous plays the
video before it; Previous and clicking items change nothing.
The runner checks autofolder's log line for the counts.
--]]

local t = require "testlib"

-- Calls a playlist action, then checks that the item `id` plays.
local function step(label, action, id)
    action()
    local ok = t.wait_for(function() return vlc.playlist.current() == id end, 5)
    t.check(label .. ": it plays", ok, "playing id " .. vlc.playlist.current() .. ", wanted " .. id)
end

t.run(function()
    local expected = {}
    if config.open then
        local user = vlc.strings.make_uri(config.user)
        vlc.playlist.enqueue({ { path = user } })
        expected[1] = t.file_name(user)
        vlc.playlist.add({ { path = vlc.strings.make_uri(config.media .. "\\" .. config.open) } })
    end

    local playing = t.wait_for(t.current_item, 5)
    if not t.check("a file is playing", playing ~= nil, "nothing playing after 5 s") then
        return
    end
    local opened = t.file_name(playing.path)
    t.info("opened " .. opened)

    local found = false
    for _, name in ipairs(t.read_lines(config.videos)) do
        if name == opened or name:sub(1, 1) ~= "." then
            expected[#expected + 1] = name
        end
        found = found or name == opened
    end
    if not t.check("the opened file is a test video", found, opened) then
        return
    end
    local order = table.concat(expected, " | ")

    -- autofolder polls every 300 ms. Wait 1 s more, so extra items would show.
    t.wait_for(function() return #t.playlist_items() >= #expected end, 5)
    t.sleep(1)
    t.equal("playlist: the user's item, then the whole folder in date order", t.playlist_names(), order)
    t.equal("the opened file still plays", vlc.playlist.current(), playing.id)
    t.equal("the opened file was started once", vlc.playlist.get(playing.id).nb_played, 1)

    local items = t.playlist_items()
    local at
    for i, item in ipairs(items) do
        if item.id == playing.id then
            at = i
        end
    end
    -- Previous, to a video autofolder added before the opened file (not to the
    -- user's item: playing that would build its folder until step C).
    local first_video = config.open and 2 or 1
    if at and at > first_video then
        step("Previous: the video before the opened file", vlc.playlist.prev, items[at - 1].id)
        t.sleep(1)
        t.equal("Previous doesn't change the playlist", t.playlist_names(), order)
    end
    if #items < 2 then
        return
    end
    -- The last item, then the opened file again (not added by autofolder, but its
    -- folder is the one built).
    step("clicking the last item", function() vlc.playlist.gotoitem(items[#items].id) end, items[#items].id)
    t.sleep(1)
    t.equal("clicking the last item doesn't change the playlist", t.playlist_names(), order)
    step("clicking the opened file", function() vlc.playlist.gotoitem(playing.id) end, playing.id)
    t.sleep(1)
    t.equal("clicking the opened file doesn't change the playlist", t.playlist_names(), order)
end)
