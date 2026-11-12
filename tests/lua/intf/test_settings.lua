--[[
The settings file (To do 3 step A): the module autofolder_settings, and
autofolder reading the file while VLC runs. run-tests.ps1 writes the file it
starts with (tools\vlc\portable\autofolder.ini, the test VLC's user folder)
and picks the scenario with config.scenario:
- parse: the module alone (no autofolder, no file playing): parsing,
         formatting, the path, and writing and reading a file in the test
         folder.
- live:  autofolder, with the file saying name-za, and Episode 2.mkv on the
         command line: the media folder is built Z to A. The driver deletes
         one item, as a user would. Then it rewrites the file (date-newest by
         hand, name-az as the dialog writes it, then a wrong value, which
         gives the default date-oldest): each time the folder is re-sorted,
         the other items are added again (new ids: VLC's playlist window
         doesn't show moves), the deleted one stays out, and Episode 2.mkv
         keeps playing. Next then plays the item after it in the new order.
         Last, the driver adds two items of its own after the folder (a
         file from Season 2\ and vlc://nop), plays the first, and switches
         to name-az: the folder is re-added whole and stays before them.
- types: autofolder, with the file setting the video types to mp4 and avi,
         and it's here.mp4 on the command line: only the mp4 and avi files
         are added. Then Episode 1.mkv is opened: no build, it isn't a video
         type now.
--]]

local t = require "testlib"
local core = require "autofolder_core"
local settings = require "autofolder_settings"

local media = config.media

-- The media folder's videos (by this script's core.is_video, without
-- dot-names, and without the name `without`) in the sort order `order`, as
-- "name | name | ...".
local function media_folder(order, without)
    local files = {}
    for _, name in ipairs(t.read_lines(config.videos)) do -- oldest first, all dates different
        if name:sub(1, 1) ~= "." and core.is_video(name) and name ~= without then
            files[#files + 1] = { name = name, mtime = #files }
        end
    end
    local names = {}
    for i, file in ipairs(core.sort_files(files, order)) do
        names[i] = file.name
    end
    return table.concat(names, " | ")
end

-- Writes the settings file as a person would in Notepad.
local function write_text(text)
    local file = vlc.io.open(settings.path(), "wb")
    if not file then
        error("cannot write " .. settings.path(), 0)
    end
    file:write(text)
    file:close()
end

local function wait_playing(name)
    local item = t.wait_for(function()
        local playing = t.current_item()
        return playing and t.file_name(playing.path) == name and playing
    end, 10)
    t.check(name .. " plays", item, "playing: " .. tostring(t.current_item() and t.current_item().path))
    return item
end

local scenarios = {}

function scenarios.parse()
    local defaults = table.concat(settings.DEFAULT_EXTENSIONS, " ")
    local d = settings.defaults()
    t.equal("defaults: sort", d.sort, "date-oldest")
    t.equal("defaults: video types", table.concat(d.extensions, " "), defaults)
    d.extensions[1] = "changed"
    t.check("defaults gives a copy of the list", settings.DEFAULT_EXTENSIONS[1] ~= "changed")

    -- "sort | types | warnings" of a file's text.
    local function parsed(text)
        local values, warnings = settings.parse(text)
        return values.sort .. " | " .. table.concat(values.extensions, " ") .. " | " .. table.concat(warnings, " / ")
    end
    t.equal("parse: an empty file gives the defaults", parsed(""), "date-oldest | " .. defaults .. " | ")
    t.equal("parse: BOM, Windows line ends, comments, spaces, any case, dots, commas, repeats",
        parsed("\239\187\191# comment\r\n; another\r\n\r\n  SORT = Name-ZA \r\nExtensions = .MP4, mkv  *.avi,MP4\r\n"),
        "name-za | mp4 mkv avi | ")
    t.equal("parse: a last line without a line end", parsed("sort=name-az"), "name-az | " .. defaults .. " | ")
    t.equal("parse: comments after a value", parsed("sort=name-za # my choice\nextensions=mp4 mkv;added mkv\n"),
        "name-za | mp4 mkv | ")
    t.equal("parse: an empty list gives the default list", parsed("extensions=\n"),
        "date-oldest | " .. defaults .. " | ")
    t.equal("parse: wrong values are warned about and give the defaults",
        parsed("sort=newest\nextensions=mp4 m?v\ncolour=red\njust text\nextensions=..\n"),
        "date-oldest | " .. defaults .. " | "
        .. 'line 1: unknown sort order "newest" (one of: date-oldest, date-newest, name-az, name-za); using date-oldest'
        .. ' / line 2: not a file extension, ignored: "m?v"'
        .. ' / line 3: not a setting, ignored: "colour=red"'
        .. ' / line 4: not a setting, ignored: "just text"'
        .. ' / line 5: not a file extension, ignored: ".."')

    for _, order in ipairs(settings.ORDERS) do
        local text = settings.format({ sort = order.id, extensions = { "mp4", "mkv" } })
        t.equal("format, then parse: " .. order.id, parsed(text), order.id .. " | mp4 mkv | ")
    end
    t.check("format writes Windows line ends", settings.format(d):find("\r\n", 1, true))

    local path = settings.path()
    t.equal("path: autofolder.ini in VLC's user folder", path,
        (vlc.config.userdatadir():gsub("[\\/]+$", "")) .. "\\autofolder.ini")
    t.info("settings path: " .. path)

    -- write and read, in the test folder (media's parent).
    local file = media:match("^(.*)\\[^\\]+$") .. "\\settings-test.ini"
    t.equal("read: a missing file is nil", settings.read(file), nil)
    t.equal("write", settings.write({ sort = "name-az", extensions = { "mkv" } }, file), true)
    t.equal("read gives back what write wrote", settings.read(file),
        settings.format({ sort = "name-az", extensions = { "mkv" } }))
    vlc.io.unlink(file)
    t.equal("read: a path that exists but can't be read (a folder) is false", settings.read(media), false)
    local ok, message = settings.write(d, media .. "\\no such folder\\x.ini")
    t.check("write into a missing folder fails with a message", not ok and message, tostring(message))
end

function scenarios.live()
    local playing = wait_playing("Episode 2.mkv")
    if not playing then
        return
    end
    if not t.expect("name-za from the settings file: the folder Z to A", media_folder("name-za")) then
        return
    end
    t.still_plays("Episode 2.mkv", playing.id)

    -- An item the user deletes stays out after a re-sort.
    local gone = "a & b.mkv"
    for _, item in ipairs(t.playlist_items()) do
        if t.file_name(item.path) == gone then
            vlc.playlist.delete(item.id)
        end
    end
    if not t.expect(gone .. " deleted by the user", media_folder("name-za", gone)) then
        return
    end

    local changes = {
        { label = "date-newest, by hand", text = "sort = date-newest\r\n", order = "date-newest" },
        { label = "name-az, as the dialog writes it", order = "name-az",
          values = { sort = "name-az", extensions = settings.DEFAULT_EXTENSIONS } },
        { label = "a wrong value: the default", text = "sort=sideways\n", order = "date-oldest" },
    }
    for _, change in ipairs(changes) do
        local before = 0
        for _, item in ipairs(t.playlist_items()) do
            before = math.max(before, item.id)
        end
        if change.values then
            t.equal(change.label .. ": written", settings.write(change.values), true)
        else
            write_text(change.text)
        end
        if not t.expect(change.label .. ": re-sorted", media_folder(change.order, gone)) then
            return
        end
        t.still_plays(change.label, playing.id)
        local old = {}
        for _, item in ipairs(t.playlist_items()) do
            if item.id ~= playing.id and item.id <= before then
                old[#old + 1] = t.file_name(item.path)
            end
        end
        t.equal(change.label .. ": the other items were added again (new ids)", table.concat(old, " | "), "")
    end

    -- Next plays the item after Episode 2.mkv in the new order.
    local items = t.playlist_items()
    local next_item
    for i, item in ipairs(items) do
        if item.id == playing.id then
            next_item = items[i + 1]
        end
    end
    if t.check("Episode 2.mkv has a next item", next_item) then
        vlc.playlist.next()
        t.check("Next plays " .. t.file_name(next_item.path),
            t.wait_for(function() return vlc.playlist.current() == next_item.id end, 5))
        t.expect("Next changes nothing", media_folder("date-oldest", gone))
    end

    -- The user's own items follow the folder, and one of them plays: the
    -- folder keeps its place, though none of its items stays where it was.
    -- The playing one isn't the last item, so it doesn't build.
    vlc.playlist.enqueue({
        { path = vlc.strings.make_uri(media .. "\\Season 2\\Episode 1.mkv") },
        { path = "vlc://nop" },
    })
    local folder_then_own = media_folder("date-oldest", gone) .. " | Episode 1.mkv | nop"
    if not t.expect("the user's items after the folder", folder_then_own) then
        return
    end
    local now = t.playlist_items()
    local own = now[#now - 1]
    vlc.playlist.gotoitem(own.id)
    if not t.check("the user's item plays", t.wait_for(function() return vlc.playlist.current() == own.id end, 5)) then
        return
    end
    t.expect("the user's item playing: no build", folder_then_own)
    write_text("sort=name-az\n")
    t.expect("a user's item playing, name-az: re-sorted, the folder in its place",
        media_folder("name-az", gone) .. " | Episode 1.mkv | nop")
    t.still_plays("the user's item", own.id)
end

function scenarios.types()
    -- This script's core gets the same video types as autofolder's.
    local text = settings.read()
    t.check("the settings file exists", text, tostring(text))
    core.set_extensions(settings.parse(text or "").extensions)
    local want = media_folder("date-oldest")
    t.info("expected: " .. want)

    local playing = wait_playing("it's here.mp4")
    if not playing then
        return
    end
    if not t.expect("only the video types of the settings file", want) then
        return
    end
    t.still_plays("it's here.mp4", playing.id)

    vlc.playlist.add({ { path = vlc.strings.make_uri(media .. "\\Episode 1.mkv") } })
    wait_playing("Episode 1.mkv")
    t.expect("Episode 1.mkv (no video type now) opened: appended, no build", want .. " | Episode 1.mkv")
end

t.run(function()
    local scenario = scenarios[config.scenario or ""]
    if not t.check("a known scenario", scenario, tostring(config.scenario)) then
        return
    end
    scenario()
end)
