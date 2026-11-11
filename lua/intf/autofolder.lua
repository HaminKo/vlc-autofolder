--[[
vlc-autofolder: a Lua interface script for VLC 3.0.x.

VLC starts it with the extra-interface setting:
    extraintf=luaintf{intf=autofolder}

When a video file starts playing, it adds the other videos of that folder to
the playlist, sorted by date modified (oldest first; equal dates by name).
The rules and the plan: docs/todo/02-interface-script.md.
So far (To do 2 step A): only the videos after the playing one are added, and
it reacts to any playing item it didn't add whose folder isn't the one built
last. Earlier files, folder switches and duplicates come in steps B and C.

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

-- Enqueues the files ({ path, ... }) in one call, in order, and marks the new
-- items as managed. Returns how many were added.
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
        wanted[uri] = true
    end
    vlc.playlist.enqueue(items)
    local added = 0
    for _, item in ipairs(playlist_items()) do
        if item.id > last and wanted[item.path] then
            managed[item.id] = true
            added = added + 1
        end
    end
    if added ~= #files then
        warn(string.format("enqueued %d files, but found %d new items", #files, added))
    end
    return added
end

-- Adds the videos of the playing file's folder that come after it in sort order.
local function build(path)
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
    core.sort_by_date(files)

    local at
    for i, file in ipairs(files) do
        if file == playing then
            at = i
        end
    end
    local later = {}
    for i = at + 1, #files do
        later[#later + 1] = files[i]
    end
    active_folder = core.path_key(folder)
    local added = enqueue(later)
    info(string.format("folder %s: %d videos, added %d after %s", folder, #files, added, name))
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
    build(path)
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
