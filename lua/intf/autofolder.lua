--[[
vlc-autofolder: a Lua interface script for VLC 3.0.x.

VLC starts it with the extra-interface setting:
    extraintf=luaintf{intf=autofolder}

When a video file starts playing, it adds the other videos of that folder to
the playlist, sorted by date modified (oldest first; equal dates by name).
The rules and the plan: docs/todo/02-interface-script.md.
So far (To do 2 step B): the whole folder is added and placed in sort order
where the playing file is; the user's own items keep their places around it.
It reacts to any playing item it didn't add whose folder isn't the one built
last. Folder switches and duplicates come in step C.

Messages start with "[autofolder]": Tools > Messages, verbosity 2.
--]]

local core = require "autofolder_core"

local POLL_US = 300000 -- 300 ms, in microseconds
local PREFIX = "[autofolder] "

local active_folder = nil -- path key of the folder built last
local managed = {}        -- id -> true for each item this script added
local last_id = -1        -- the playing item's id at the previous poll

local function info(text)
    vlc.msg.info(PREFIX .. text)
end

local function dbg(text)
    vlc.msg.dbg(PREFIX .. text)
end

local function warn(text)
    vlc.msg.warn(PREFIX .. text)
end

local function playlist_items()
    return vlc.playlist.get("playlist").children or {}
end

-- Enqueues the files ({ path, ... }) in one call, in order (they are appended),
-- marks the new items as managed and sets each file's `id`. Returns how many
-- were added.
local function enqueue(files)
    if #files == 0 then
        return 0
    end
    -- New items get higher ids than every item before them (measured).
    local last = 0
    for _, item in ipairs(playlist_items()) do
        last = math.max(last, item.id)
    end
    local items, wanted = {}, {}
    for i, file in ipairs(files) do
        local uri = vlc.strings.make_uri(file.path)
        items[i] = { path = uri }
        wanted[uri] = file
    end
    vlc.playlist.enqueue(items)
    local added = 0
    for _, item in ipairs(playlist_items()) do
        local file = item.id > last and wanted[item.path]
        if file and not file.id then
            file.id = item.id
            managed[item.id] = true
            added = added + 1
        end
    end
    if added ~= #files then
        warn(string.format("enqueued %d files, but found %d new items", #files, added))
    end
    return added
end

-- Puts the folder's items (ids in sort order) together, in that order, where
-- the folder's first item is now; the user's own items keep their order around
-- them (core.target_order). Moves only to the front of the playlist node:
-- VLC 3.0's move after an item is broken (docs/decisions.md). Returns the
-- number of moves.
local function arrange(folder_ids)
    local node = vlc.playlist.get("playlist")
    local current = {}
    for i, item in ipairs(node.children or {}) do
        current[i] = item.id
    end
    local moves = core.front_moves(current, core.target_order(current, folder_ids))
    for _, id in ipairs(moves) do
        if vlc.playlist.move(id, node.id) ~= 0 then
            warn("cannot move item " .. id .. " (removed meanwhile?)")
        end
    end
    return #moves
end

-- Adds the other videos of the playing file's folder (the item `id`, path
-- `path`) and puts the folder in sort order around it.
local function build(path, id)
    local folder, name = core.split_path(path)
    -- The scan doesn't wait (no mwait), so catching its errors is safe.
    local ok, files = pcall(core.scan_folder, folder)
    if not ok then
        warn("cannot read the folder " .. folder .. ": " .. tostring(files))
        return
    end

    local key = core.path_key(path)
    local playing
    for _, file in ipairs(files) do
        if core.path_key(file.path) == key then
            playing = file
        end
    end
    if not playing then
        -- The scan skips names starting with ".", but the user opened one: place
        -- it by its own date. Any other miss would risk adding the file twice.
        local stat = name:sub(1, 1) == "." and vlc.net.stat(path)
        if not stat then
            warn("the playing file is not in its folder's list: " .. path)
            return
        end
        playing = { name = name, path = path, mtime = stat.modification_time }
        files[#files + 1] = playing
    end
    playing.id = id
    core.sort_by_date(files)

    -- Enqueue the others in sort order, in one call; arrange then moves them.
    local others = {}
    for _, file in ipairs(files) do
        if file ~= playing then
            others[#others + 1] = file
        end
    end
    active_folder = core.path_key(folder)
    enqueue(others)

    local folder_ids, before = {}, 0
    for _, file in ipairs(files) do
        if file.id then
            folder_ids[#folder_ids + 1] = file.id
            if file == playing then
                before = #folder_ids - 1
            end
        end
    end
    local after = #folder_ids - 1 - before
    local moves = arrange(folder_ids)
    info(string.format("folder %s: %d videos; added %d before and %d after %s; %d moves",
        folder, #files, before, after, name, moves))
end

-- Called when the playing item changes to `id`.
local function on_playing(id)
    if managed[id] then
        return -- an item this script added: clicked, or reached with Next/Previous
    end
    local item = vlc.playlist.get(id)
    if not item then
        return
    end
    local path = core.uri_to_path(item.path)
    if not path then
        dbg("not a local file: " .. tostring(item.path))
        return
    end
    local folder, name = core.split_path(path)
    if not folder or not core.is_video(name) then
        dbg("not a video file: " .. path)
        return
    end
    if core.path_key(folder) == active_folder then
        dbg("folder already built: " .. folder)
        return
    end
    build(path, id)
end

local function poll()
    local id = vlc.playlist.current()
    if id ~= last_id then
        last_id = id -- set first, so a failing item isn't retried on every poll
        if id ~= -1 then
            on_playing(id)
        end
    end
end

info("started")

-- Never wrap mwait in pcall: when VLC closes, mwait raises "Interrupted.",
-- and that error must end this script, or VLC can hang on close.
while true do
    -- A bug in one poll is logged and doesn't stop the script. poll never
    -- waits, so this pcall can't catch the "Interrupted." of VLC closing.
    local ok, err = pcall(poll)
    if not ok then
        vlc.msg.err(PREFIX .. tostring(err))
    end
    vlc.misc.mwait(vlc.misc.mdate() + POLL_US)
end
