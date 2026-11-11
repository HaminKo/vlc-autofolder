--[[
Building the folder (To do 2 step A). run-tests.ps1 starts it next to
autofolder, with one test video on VLC's command line, like a double-click.
Expected: the playlist becomes the opened file, then the videos that come
after it in date order (videos.txt, without names starting with "."), and the
opened file keeps playing. Clicking items afterwards changes nothing.
The runner checks autofolder's log line for the counts.
--]]

local t = require "testlib"

-- Plays the item with this id and waits until it plays.
local function click(label, id)
    vlc.playlist.gotoitem(id)
    local ok = t.wait_for(function() return vlc.playlist.current() == id end, 5)
    t.check(label .. ": it plays", ok, "playing id " .. vlc.playlist.current() .. ", wanted " .. id)
end

t.run(function()
    local playing = t.wait_for(t.current_item, 5)
    if not t.check("a file is playing", playing ~= nil, "nothing playing after 5 s") then
        return
    end
    local opened = t.file_name(playing.path)
    t.info("opened " .. opened)

    local expected, found = {}, false
    for _, name in ipairs(t.read_lines(config.videos)) do
        if name == opened then
            found = true
            expected[#expected + 1] = name
        elseif found and name:sub(1, 1) ~= "." then
            expected[#expected + 1] = name
        end
    end
    if not t.check("the opened file is a test video", found, opened) then
        return
    end
    local order = table.concat(expected, " | ")

    -- autofolder polls every 300 ms. Wait 1 s more, so extra items would show.
    t.wait_for(function() return #t.playlist_items() >= #expected end, 5)
    t.sleep(1)
    t.equal("playlist: the opened file, then the later videos in date order", t.playlist_names(), order)
    t.equal("the opened file still plays", vlc.playlist.current(), playing.id)
    t.equal("the opened file was started once", vlc.playlist.get(playing.id).nb_played, 1)

    if #expected < 2 then
        return
    end
    -- An item autofolder added, then the opened file again (not added by
    -- autofolder, but its folder is the one built).
    local items = t.playlist_items()
    click("clicking the last item", items[#items].id)
    t.sleep(1)
    t.equal("clicking the last item doesn't change the playlist", t.playlist_names(), order)
    click("clicking the opened file", playing.id)
    t.sleep(1)
    t.equal("clicking the opened file doesn't change the playlist", t.playlist_names(), order)
end)
