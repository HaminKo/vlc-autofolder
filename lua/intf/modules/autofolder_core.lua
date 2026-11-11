--[[
Helpers for autofolder.lua that don't change the playlist: paths and URIs,
the video filter, natural name order, the folder scan, and the decisions
(when to build, which items to remove, the order to reach). Load with:
    local core = require "autofolder_core"
Tests: tests\lua\intf\test_core.lua.

Paths are Windows paths in UTF-8 (as vlc.net and vlc.io take them).
String comparisons here go byte by byte: Lua's "<" on strings uses the C
locale's collation, which could differ between PCs.
--]]

local M = {}

-- File extensions that count as video, lower case (To do 3 makes them configurable).
M.VIDEO_EXTENSIONS = {
    "mp4", "mkv", "avi", "mov", "wmv", "webm", "m4v", "flv", "ts", "mpg", "mpeg",
    "m2ts", "mts", "3gp", "ogv", "vob",
}

local video_set = {}
for _, ext in ipairs(M.VIDEO_EXTENSIONS) do
    video_set[ext] = true
end

-- An item "plays straight away" when it starts at most this many seconds after
-- it became the playlist's last item (docs/decisions.md).
M.JUST_OPENED_S = 10

-- Lower-cases ASCII letters only. string.lower depends on the C locale and
-- could change the bytes of UTF-8 characters.
local function ascii_lower(s)
    return (s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end))
end

-- -1, 0 or 1, comparing two strings byte by byte.
local function compare_bytes(a, b)
    if a == b then
        return 0
    end
    for i = 1, math.min(#a, #b) do
        local x, y = a:byte(i), b:byte(i)
        if x ~= y then
            return x < y and -1 or 1
        end
    end
    return #a < #b and -1 or 1
end

-- The local path of a file:// URI, or nil for any other URI.
--   file:///C:/My%20Videos/a.mkv   -> C:\My Videos\a.mkv
--   file://server/share/a.mkv      -> \\server\share\a.mkv (UNC)
--   file://localhost/C:/a.mkv      -> C:\a.mkv (another way to write a local file)
-- vlc.strings.make_path would drop the server of a UNC URI (measured).
function M.uri_to_path(uri)
    if type(uri) ~= "string" then
        return nil
    end
    local rest = uri:match("^[Ff][Ii][Ll][Ee]://(.+)$")
    if not rest then
        return nil
    end
    local drive = rest:match("^[Ll][Oo][Cc][Aa][Ll][Hh][Oo][Ss][Tt](/[A-Za-z]:.*)$")
    if drive then
        rest = drive
    end
    local path
    if rest:sub(1, 1) == "/" then
        path = rest:sub(2) -- a drive: C:/...
    else
        path = "//" .. rest -- a server: server/share/...
    end
    path = vlc.strings.decode_uri(path)
    return (path:gsub("/", "\\"))
end

-- The folder (with its trailing backslash) and the file name of a path, or nil.
--   C:\Videos\a.mkv -> "C:\Videos\", "a.mkv"
function M.split_path(path)
    local folder, name = path:match("^(.*[\\/])([^\\/]+)$")
    if not folder then
        return nil
    end
    return (folder:gsub("/", "\\")), name
end

-- A key for comparing paths: "/" as "\" and ASCII letters lower-cased, since
-- Windows ignores case in file names.
function M.path_key(path)
    return ascii_lower((path:gsub("/", "\\")))
end

-- True for a file name with a video extension (any case).
function M.is_video(name)
    local ext = name:match("%.([^.\\/]+)$")
    return ext ~= nil and video_set[ascii_lower(ext)] == true
end

local function is_digit(byte)
    return byte ~= nil and byte >= 48 and byte <= 57 -- "0" to "9"
end

-- Where a run of digits starting at i ends (the index after it), and where its
-- number starts once leading zeros are skipped (the last zero is kept).
local function digit_run(s, i)
    local stop = i
    while is_digit(s:byte(stop)) do
        stop = stop + 1
    end
    local start = i
    while start < stop - 1 and s:byte(start) == 48 do
        start = start + 1
    end
    return start, stop
end

-- -1, 0 or 1 in natural order: runs of digits by their value (Episode 2 before
-- Episode 10), everything else byte by byte with ASCII letters lower-cased
-- (a and b are already lower-cased). Walks both names character by character,
-- so "Show.mkv" comes before "Show2.mkv", as "." comes before "2".
local function compare_natural(a, b)
    local i, j = 1, 1
    while i <= #a and j <= #b do
        local x, y = a:byte(i), b:byte(j)
        if is_digit(x) and is_digit(y) then
            local a_start, a_stop = digit_run(a, i)
            local b_start, b_stop = digit_run(b, j)
            local a_len, b_len = a_stop - a_start, b_stop - b_start
            if a_len ~= b_len then
                return a_len < b_len and -1 or 1 -- fewer digits: smaller number
            end
            local c = compare_bytes(a:sub(a_start, a_stop - 1), b:sub(b_start, b_stop - 1))
            if c ~= 0 then
                return c
            end
            i, j = a_stop, b_stop
        elseif x ~= y then
            return x < y and -1 or 1
        else
            i, j = i + 1, j + 1
        end
    end
    if i <= #a then
        return 1 -- b ended first
    elseif j <= #b then
        return -1
    end
    return 0
end

-- -1, 0 or 1 for two files ({ name, lower }): natural order; names equal that
-- way (Episode 01 and Episode 1, or a and A) go by their bytes, so the order is
-- always the same.
local function compare_names(a, b)
    local c = compare_natural(a.lower, b.lower)
    if c ~= 0 then
        return c
    end
    return compare_bytes(a.name, b.name)
end

-- True when name a comes before name b in natural order.
function M.natural_less(a, b)
    return compare_names({ name = a, lower = ascii_lower(a) }, { name = b, lower = ascii_lower(b) }) < 0
end

-- Sorts a list of files ({ name, mtime, ... }) in place: date modified, oldest
-- first, then natural name order. Returns the list.
function M.sort_by_date(files)
    for _, file in ipairs(files) do
        file.lower = file.lower or ascii_lower(file.name)
    end
    table.sort(files, function(a, b)
        if a.mtime ~= b.mtime then
            return a.mtime < b.mtime
        end
        return compare_names(a, b) < 0
    end)
    return files
end

-- The videos in a folder (a path ending in a backslash), unsorted: a list of
-- { name, path, mtime }. Skips subfolders, names starting with "." (also "."
-- and "..") and other file types. Raises an error if the folder can't be read.
function M.scan_folder(folder)
    local files = {}
    for _, name in ipairs(vlc.net.opendir(folder)) do
        if name:sub(1, 1) ~= "." and M.is_video(name) then
            local path = folder .. name
            local info = vlc.net.stat(path)
            if info and info.type == "file" then
                files[#files + 1] = { name = name, path = path, mtime = info.modification_time }
            end
        end
    end
    return files
end

-- Whether the item `id`, which just started playing, was just opened (a
-- double-click, Open File, a drop onto the window), so its folder is built:
--   - it was added after the previous item started: its id is above
--     started_max, the highest id in the playlist then (ids only grow);
--   - it is the playlist's last item (`last`): opened files are appended. The
--     position, not the highest id, since VLC may number the files of its
--     command line in another order;
--   - it plays straight away: it has been the last item for at most
--     JUST_OPENED_S seconds (`last_for_s`). The first item to play after VLC
--     starts always counts (`first_play`): a cold start can take longer.
-- Returns true, or false and the reason.
function M.just_opened(id, last, started_max, last_for_s, first_play)
    if id ~= last then
        return false, "not the last item"
    elseif id <= started_max then
        return false, "added before the previous item started"
    elseif not first_play and last_for_s > M.JUST_OPENED_S then
        return false, string.format("added %.1f s before it started", last_for_s)
    end
    return true
end

-- Matches the playlist's items to the files of a folder scan: each file that an
-- item plays gets that item's id (file.id). One item per file: the playing item
-- `opened` wins, otherwise the first one in the playlist; the other copies'
-- ids go into file.copies. Returns the ids to delete: those copies, and items
-- in the folder whose file is gone.
-- items: the playlist's items in order ({ id, path = URI }). folder: the
-- folder's path. files: the scan ({ path, ... }, the opened file included).
-- exists(path): true when the file is still there. Items in other folders
-- (subfolders too) and non-videos are left alone; the opened item is never
-- deleted.
function M.match_items(items, folder, files, opened, exists)
    local by_key = {}
    for _, file in ipairs(files) do
        by_key[M.path_key(file.path)] = file
    end
    local folder_key = M.path_key(folder)
    local delete = {}
    for _, item in ipairs(items) do
        local path = M.uri_to_path(item.path)
        local dir, name
        if path then
            dir, name = M.split_path(path)
        end
        if dir and M.path_key(dir) == folder_key and M.is_video(name) then
            local file = by_key[M.path_key(path)]
            if not file then
                if item.id ~= opened and not exists(path) then
                    delete[#delete + 1] = item.id
                end
            elseif not file.id then
                file.id = item.id
            else
                local copy = item.id
                if item.id == opened then
                    copy, file.id = file.id, item.id -- the earlier copy goes
                end
                delete[#delete + 1] = copy
                file.copies = file.copies or {}
                file.copies[#file.copies + 1] = copy
            end
        end
    end
    return delete
end

-- The order the playlist should have once the folder is placed: the items
-- before the folder's first item (the user's own), then the folder's items in
-- sort order, then all other items in their current order. So the folder takes
-- the place of its first item, as when VLC opens a folder itself.
-- current: the playlist's item ids, in order. folder: the folder's ids in sort
-- order; ids that are not in current are left out. Returns a list of ids.
function M.target_order(current, folder)
    local present, in_folder = {}, {}
    for _, id in ipairs(current) do
        present[id] = true
    end
    for _, id in ipairs(folder) do
        in_folder[id] = true
    end
    local before, after, seen = {}, {}, false
    for _, id in ipairs(current) do
        if in_folder[id] then
            seen = true
        elseif seen then
            after[#after + 1] = id
        else
            before[#before + 1] = id
        end
    end
    local target = before
    for _, id in ipairs(folder) do
        if present[id] then
            target[#target + 1] = id
        end
    end
    for _, id in ipairs(after) do
        target[#target + 1] = id
    end
    return target
end

-- The fewest moves "to the front of the playlist" that turn the order current
-- into target (two lists of the same ids): the ids to move, one after another.
-- Items that are never moved keep their order and end up after the moved
-- ones. So the longest end part of target that is already in current's order
-- stays; every item before it is moved, last one first.
function M.front_moves(current, target)
    local pos = {}
    for i, id in ipairs(current) do
        pos[id] = i
    end
    local keep = #target + 1 -- target[keep], target[keep + 1], ... stay
    while keep > 1 do
        local p = pos[target[keep - 1]]
        if not p or (keep <= #target and p > pos[target[keep]]) then
            break
        end
        keep = keep - 1
    end
    local moves = {}
    for i = keep - 1, 1, -1 do
        moves[#moves + 1] = target[i]
    end
    return moves
end

return M
