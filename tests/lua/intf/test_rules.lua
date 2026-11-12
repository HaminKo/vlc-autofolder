--[[
The playlist rules (To do 2 step C): when a folder is built, a folder switch,
the refresh of the same folder, and the cases that never build.
run-tests.ps1 starts it next to autofolder; config.scenario picks the case:
- switch:   the user's items summer.mkv and media\Episode 1.mkv, then
            Episode 1.mkv opened (VLC appends a second copy): the media folder
            is built with one copy, the opened one, which stays the user's.
            Then a file of media\Season 2 opened: the media items go, the
            user's items stay, Season 2 is built. Clicking the user's item
            changes nothing.
- refresh:  refresh\b.mkv opened (a build: a, b, c), then the user's item
            summer.mkv enqueued after it. Then c.mkv is deleted, d.mkv
            created, and a.mkv opened again (VLC appends a copy): summer.mkv,
            then one copy of a, the playing one, then b, d (the folder goes
            where the opened copy is). Then the playlist is cleared and b.mkv
            opened again: the folder is built again.
- reopen:   Episode 2.mkv opened (a build), then opened again: the folder
            with the new copy in the old one's place (the user's report in
            To do 6).
In the builds after the first, the items that keep their id must keep their
order, since VLC's playlist window doesn't show a script's moves
(testlib.kept_order).
- no-build: VLC opened the files on its command line (several files, or an
            .m3u); the playlist must stay config.expect, also after Next.
- late:     a media file opened (a build), then an item enqueued and clicked
            more than core.JUST_OPENED_S seconds later: no build.
Playlist entries are shown as paths relative to the test folder, e.g.
"media\Season 2\Episode 1.mkv".
--]]

local t = require "testlib"
local core = require "autofolder_core"

local media = config.media
local root = media:match("^(.*)\\[^\\]+$") -- the test folder, media's parent

local function uri(path)
    return vlc.strings.make_uri(path)
end

-- A playlist item's path relative to the test folder (or its URI).
local function rel(item)
    local path = core.uri_to_path(item.path)
    if path and path:sub(1, #root + 1) == root .. "\\" then
        return path:sub(#root + 2)
    end
    return path or item.path
end

local function names()
    local list = {}
    for _, item in ipairs(t.playlist_items()) do
        list[#list + 1] = rel(item)
    end
    return table.concat(list, " | ")
end

local function find(name)
    for _, item in ipairs(t.playlist_items()) do
        if rel(item) == name then
            return item
        end
    end
end

-- Opens a file like a double-click into a running VLC: appended and played.
local function open(path)
    vlc.playlist.add({ { path = uri(path) } })
end

-- Waits until the item `name` plays, other than the item `not_id`; returns it.
local function wait_playing(name, not_id)
    local item = t.wait_for(function()
        local playing = t.current_item()
        return playing and rel(playing) == name and playing.id ~= not_id and playing
    end, 10)
    t.check(name .. " plays", item, "playing: " .. tostring(t.current_item() and rel(t.current_item())))
    return item
end

-- Waits until the playlist is `want`, then checks it (t.expect).
local function expect(label, want)
    return t.expect(label, want, names)
end

local function still_plays(label, item)
    t.still_plays(label, item.id)
end

-- Plays the item by id (a click in the playlist) and checks that it plays.
local function click(item)
    vlc.playlist.gotoitem(item.id)
    local ok = t.wait_for(function() return vlc.playlist.current() == item.id end, 5)
    t.check("clicking " .. rel(item) .. ": it plays", ok)
end

-- The media folder's videos in date order, without dot-names: "media\..." each.
local function media_folder()
    local list = {}
    for _, name in ipairs(t.read_lines(config.videos)) do
        if name:sub(1, 1) ~= "." then
            list[#list + 1] = "media\\" .. name
        end
    end
    return table.concat(list, " | ")
end

local function copy_file(from, to)
    local input = vlc.io.open(from, "rb")
    if not input then
        error("cannot read " .. from, 0)
    end
    local data = input:read("*a")
    input:close()
    local output = vlc.io.open(to, "wb")
    if not output then
        error("cannot write " .. to, 0)
    end
    output:write(data)
    output:close()
end

local scenarios = {}

function scenarios.switch()
    vlc.playlist.enqueue({ { path = uri(root .. "\\summer.mkv") }, { path = uri(media .. "\\Episode 1.mkv") } })
    local own = find("media\\Episode 1.mkv")
    local shown = t.playlist_ids()
    open(media .. "\\Episode 1.mkv")
    local first = wait_playing("media\\Episode 1.mkv", own and own.id)
    if not expect("the user's item, then the media folder with one copy of Episode 1.mkv",
            "summer.mkv | " .. media_folder()) then
        return
    end
    still_plays("Episode 1.mkv", first)
    shown[#shown + 1] = first.id
    t.equal("Episode 1.mkv opened: the items that kept their id",
        t.kept_order("Episode 1.mkv opened", shown), "summer.mkv | Episode 1.mkv")

    open(media .. "\\Season 2\\Episode 1.mkv")
    local second = wait_playing("media\\Season 2\\Episode 1.mkv")
    expect("switch: the added media items are gone, the user's items stay, Season 2 is built",
        "summer.mkv | media\\Episode 1.mkv | media\\Season 2\\Episode 1.mkv | media\\Season 2\\Episode 2.mkv")
    still_plays("Season 2\\Episode 1.mkv", second)

    local before = names()
    click(find("summer.mkv"))
    expect("clicking the user's item (another folder) changes nothing", before)
end

function scenarios.refresh()
    local dir = root .. "\\refresh"
    open(dir .. "\\b.mkv")
    wait_playing("refresh\\b.mkv")
    if not expect("b.mkv opened: the folder", "refresh\\a.mkv | refresh\\b.mkv | refresh\\c.mkv") then
        return
    end

    -- The user adds an item of their own after the folder.
    vlc.playlist.enqueue({ { path = uri(root .. "\\summer.mkv") } })
    if not expect("the user's item after the folder",
            "refresh\\a.mkv | refresh\\b.mkv | refresh\\c.mkv | summer.mkv") then
        return
    end

    -- The folder changes while VLC runs: c.mkv deleted, d.mkv new (dated now: last).
    vlc.io.unlink(dir .. "\\c.mkv")
    t.check("c.mkv deleted", not vlc.net.stat(dir .. "\\c.mkv"))
    copy_file(dir .. "\\a.mkv", dir .. "\\d.mkv")
    local old_a = find("refresh\\a.mkv")
    local shown = t.playlist_ids()
    open(dir .. "\\a.mkv") -- VLC appends a second copy of a.mkv and plays it
    local a = wait_playing("refresh\\a.mkv", old_a and old_a.id)
    -- The folder goes where the opened copy is, after the user's item, which
    -- isn't added again; b.mkv, before summer.mkv until now, is.
    expect("a.mkv opened again: the user's item, then one copy of a, b, the new d; c is gone",
        "summer.mkv | refresh\\a.mkv | refresh\\b.mkv | refresh\\d.mkv")
    if a then
        still_plays("the second copy of a.mkv", a)
        shown[#shown + 1] = a.id
        t.equal("a.mkv opened again: the items that kept their id",
            t.kept_order("a.mkv opened again", shown), "summer.mkv | a.mkv")
    end

    -- The step A gap: after the playlist was cleared, the same folder is built again.
    vlc.playlist.clear()
    t.wait_for(function() return #t.playlist_items() == 0 end, 5)
    open(dir .. "\\b.mkv")
    local b = wait_playing("refresh\\b.mkv")
    expect("cleared, then b.mkv opened: the folder again", "refresh\\a.mkv | refresh\\b.mkv | refresh\\d.mkv")
    if b then
        still_plays("b.mkv", b)
    end
end

-- The user's report (To do 6): the media folder built from Episode 2.mkv,
-- then Episode 2.mkv opened again. Its new copy plays in the old copy's place
-- (2nd by date). It was shown last, so the items after it by date are added
-- again; the one before it keeps its id.
function scenarios.reopen()
    local first = wait_playing("media\\Episode 2.mkv")
    if not expect("Episode 2.mkv opened: the media folder", media_folder()) then
        return
    end
    local shown = t.playlist_ids()
    open(media .. "\\Episode 2.mkv")
    local again = wait_playing("media\\Episode 2.mkv", first and first.id)
    expect("Episode 2.mkv opened again: the folder with one copy of it, in its place", media_folder())
    if again then
        still_plays("the second copy of Episode 2.mkv", again)
        shown[#shown + 1] = again.id
        t.equal("Episode 2.mkv opened again: the items that kept their id",
            t.kept_order("Episode 2.mkv opened again", shown), "Episode 10.mkv | Episode 2.mkv")
    end
end

function scenarios.no_build()
    -- An .m3u plays first and is replaced by its entries; then its first entry plays.
    local want = config.expect
    t.wait_for(function() return names() == want and vlc.playlist.current() ~= -1 end, 10)
    local items = t.playlist_items()
    local ids = {}
    for i, item in ipairs(items) do
        ids[i] = rel(item) .. "=" .. item.id
    end
    t.info("ids in playlist order: " .. table.concat(ids, ", "))
    t.info("playing: " .. tostring(t.current_item() and rel(t.current_item())))
    expect("the playlist stays as VLC opened it", want)
    if #items >= 2 then
        local playing = vlc.playlist.current()
        local at
        for i, item in ipairs(items) do
            if item.id == playing then
                at = i
            end
        end
        local next_item = at and items[at + 1]
        if t.check("the playing item has a next item", next_item,
                "playing id " .. playing .. (at and " is the last item" or " is not in the playlist")) then
            vlc.playlist.next()
            t.check("Next plays the next item",
                t.wait_for(function() return vlc.playlist.current() == next_item.id end, 5))
            expect("Next changes nothing", want)
        end
    end
end

function scenarios.late()
    wait_playing("media\\Episode 2.mkv")
    if not expect("Episode 2.mkv opened: the media folder", media_folder()) then
        return
    end
    vlc.playlist.enqueue({ { path = uri(media .. "\\Season 2\\Episode 1.mkv") } })
    local want = media_folder() .. " | media\\Season 2\\Episode 1.mkv"
    expect("enqueued: appended", want)
    t.sleep(core.JUST_OPENED_S + 1)
    click(find("media\\Season 2\\Episode 1.mkv"))
    expect("clicked " .. (core.JUST_OPENED_S + 1) .. " s after it was added: no build", want)
end

t.run(function()
    local scenario = scenarios[(config.scenario or ""):gsub("-", "_")]
    if not t.check("a known scenario", scenario, tostring(config.scenario)) then
        return
    end
    scenario()
end)
