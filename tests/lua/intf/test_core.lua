--[[
The helper module autofolder_core, run inside the real VLC (its Lua 5.1 and
its vlc.* functions). run-tests.ps1 starts it alone, with no file to play.
--]]

local t = require "testlib"
local core = require "autofolder_core"

-- Checks fn(x) for each x in list; one result line, naming the items that failed.
local function each(label, list, fn)
    local bad = {}
    for _, x in ipairs(list) do
        local ok, message = fn(x)
        if not ok then
            bad[#bad + 1] = tostring(x) .. (message and (" -> " .. message) or "")
        end
    end
    t.check(label, #bad == 0, "failed for: " .. table.concat(bad, "; "))
end

local function names_of(files)
    local names = {}
    for i, file in ipairs(files) do
        names[i] = file.name
    end
    return table.concat(names, " | ")
end

local function is_dot_name(name)
    return name:sub(1, 1) == "."
end

t.run(function()
    local media = config.media
    local videos = t.read_lines(config.videos) -- oldest first

    -- uri_to_path
    each("uri_to_path gives back every test path (Unicode, #, %, a literal %20, ...)", videos, function(name)
        local path = media .. "\\" .. name
        local back = core.uri_to_path(vlc.strings.make_uri(path))
        return back == path, tostring(back)
    end)
    local unc = config.unc .. "\\Episode 1.mkv"
    t.equal("uri_to_path of a UNC URI", core.uri_to_path(vlc.strings.make_uri(unc)), unc)
    t.equal("uri_to_path of a hand-written URI",
        core.uri_to_path("file:///C:/My%20Videos/a%23b.mkv"), "C:\\My Videos\\a#b.mkv")
    t.equal("uri_to_path of a local URI with localhost",
        core.uri_to_path("file://localhost/C:/My%20Videos/a.mkv"), "C:\\My Videos\\a.mkv")
    each("uri_to_path of other URIs is nil", { "http://example.com/a.mkv", "dvd:///D:/", "C:\\a.mkv", "file://" },
        function(uri)
            local path = core.uri_to_path(uri)
            return path == nil, tostring(path)
        end)

    -- split_path and path_key
    local function split(path)
        local folder, name = core.split_path(path)
        return tostring(folder) .. "|" .. tostring(name)
    end
    t.equal("split_path", split("C:\\Videos\\a.mkv"), "C:\\Videos\\|a.mkv")
    t.equal("split_path at a drive root", split("C:\\a.mkv"), "C:\\|a.mkv")
    t.equal("split_path of a UNC path", split("\\\\server\\share\\a.mkv"), "\\\\server\\share\\|a.mkv")
    t.equal("split_path of a folder", split("C:\\Videos\\"), "nil|nil")
    t.equal("path_key ignores ASCII case and slash direction",
        core.path_key("C:/Videos/A.MKV"), core.path_key("c:\\videos\\a.mkv"))
    t.equal("path_key keeps non-ASCII bytes", core.path_key("\195\137.mkv"), "\195\137.mkv") -- É

    -- is_video
    each("is_video", { "a.mkv", "b.MP4", "c.Ts", "d.m2ts", "e.vob", "x.y.webm" }, function(name)
        return core.is_video(name)
    end)
    each("not is_video", { "a.srt", "b.jpg", "c.m3u", "d.xspf", "mkv", "e.", "Season 2", "f.mkv.txt" },
        function(name)
            return not core.is_video(name)
        end)

    -- Natural order: each name comes before every name after it, and not after.
    local order = {
        "1.mkv", "2.mkv", "10.mkv", "a.mkv",
        "cafe.mkv", "caf\195\169.mkv", -- café: non-ASCII bytes after ASCII letters
        "Episode 01.mkv", "Episode 1.mkv", "Episode 2.mkv", "episode 3.MP4",
        "Episode 10.mkv", "Episode 10b.mkv", "Episode 100.mkv",
        "S1E9.mkv", "S01E10.mkv", "S2E1.mkv",
        "x 99999999999999999999.mkv", "x 100000000000000000000.mkv", -- beyond a Lua number's precision
    }
    local wrong = {}
    for i = 1, #order do
        for j = i + 1, #order do
            if not core.natural_less(order[i], order[j]) or core.natural_less(order[j], order[i]) then
                wrong[#wrong + 1] = order[i] .. " / " .. order[j]
            end
        end
    end
    t.check("natural order", #wrong == 0, "wrong for: " .. table.concat(wrong, "; "))
    -- A name that ends where the other has a number: "." comes before "2".
    each("natural order when one name's text is a prefix of the other's",
        { { "Show.mkv", "Show2.mkv" }, { "a.mkv", "a1.mkv" }, { "Part 2.mkv", "Part 2a.mkv" } },
        function(pair)
            return core.natural_less(pair[1], pair[2]) and not core.natural_less(pair[2], pair[1]),
                pair[1] .. " / " .. pair[2]
        end)
    t.check("natural_less is false for the same name", not core.natural_less("Episode 1.mkv", "Episode 1.mkv"))

    -- sort_by_date: oldest first, equal dates in natural order.
    local files = {
        { name = "Episode 10.mkv", mtime = 5 }, { name = "b.mkv", mtime = 9 },
        { name = "Episode 2.mkv", mtime = 5 }, { name = "a.mkv", mtime = 1 },
    }
    t.equal("sort_by_date", names_of(core.sort_by_date(files)), "a.mkv | Episode 2.mkv | Episode 10.mkv | b.mkv")

    -- scan_folder on the test media: videos only (no .srt .jpg .txt .nfo .m3u, no
    -- subfolder, no dot-name; the attribute-hidden file is kept), in date order.
    local expected = {}
    for _, name in ipairs(videos) do
        if not is_dot_name(name) then
            expected[#expected + 1] = name
        end
    end
    local scanned = core.sort_by_date(core.scan_folder(media .. "\\"))
    t.equal("scan_folder: the videos, in date order", names_of(scanned), table.concat(expected, " | "))
    t.equal("scan_folder: full paths", scanned[1] and scanned[1].path, media .. "\\" .. expected[1])
    local ok = pcall(core.scan_folder, media .. "\\no such folder\\")
    t.check("scan_folder raises an error for a missing folder", not ok)

    -- target_order and front_moves, on lists of ids. Folder ids are episode
    -- numbers; 91, 92 are the user's own items. apply() replays the moves as
    -- VLC does them: each id goes to the front.
    local function apply(current, moves)
        local list = {}
        for i, id in ipairs(current) do
            list[i] = id
        end
        for _, id in ipairs(moves) do
            for i, x in ipairs(list) do
                if x == id then
                    table.remove(list, i)
                    break
                end
            end
            table.insert(list, 1, id)
        end
        return table.concat(list, " ")
    end
    -- { label, current playlist, folder in sort order, expected order, expected moves }
    local arrangements = {
        { "already in order", { 1, 2, 3 }, { 1, 2, 3 }, "1 2 3", 0 },
        { "opened in the middle", { 3, 1, 2, 4, 5 }, { 1, 2, 3, 4, 5 }, "1 2 3 4 5", 2 },
        { "opened last", { 5, 1, 2, 3, 4 }, { 1, 2, 3, 4, 5 }, "1 2 3 4 5", 4 },
        { "user items before the folder stay before it", { 91, 92, 3, 1, 2, 4, 5 }, { 1, 2, 3, 4, 5 },
            "91 92 1 2 3 4 5", 4 },
        { "a user item inside the folder goes after it", { 1, 91, 2, 3, 92 }, { 1, 2, 3 }, "1 2 3 91 92", 3 },
        { "a folder id not in the playlist is left out", { 3, 1 }, { 1, 2, 3 }, "1 3", 1 },
        { "an empty playlist", {}, {}, "", 0 },
    }
    each("target_order and front_moves", arrangements, function(case)
        local label, current, folder, want, want_moves = case[1], case[2], case[3], case[4], case[5]
        local target = core.target_order(current, folder)
        local moves = core.front_moves(current, target)
        local got = apply(current, moves)
        local message = string.format("%s: target %s, after the moves %s, %d moves",
            label, table.concat(target, " "), got, #moves)
        return table.concat(target, " ") == want and got == want and #moves == want_moves, message
    end)
end)
