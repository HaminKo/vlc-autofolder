--[[
vlc-autofolder: a Lua interface script for VLC 3.0.x.

VLC starts it with the extra-interface setting:
    extraintf=luaintf{intf=autofolder}

When a video file is opened (a double-click, Open File, a drop onto the
window), it adds the other videos of that folder to the playlist, in the sort
order of the settings (date modified, oldest first, by default), and puts the
folder in that order where the opened file is: at the end. The user's own
items keep their order before it.
- VLC's playlist window doesn't show a script's moves, so the folder items
  that must change their order are deleted and added again (place).
- The settings file (autofolder_settings: the sort order and the video types)
  is read at start and about every second. A new sort order re-sorts the
  folder at once; new video types apply to the next file opened.
- Only a file that was just opened builds (core.just_opened): playing an item
  that was already in the playlist never changes it.
- A file from another folder: the previous folder's items this script added,
  and the file opened there, are removed first.
- The same folder again: it is refreshed. One copy per file, files that are
  new in the folder are added, items whose file is gone are removed.
The rules and the plan: docs/archive/02-interface-script.md, docs/decisions.md.

Messages start with "[autofolder]": Tools > Messages, verbosity 2.
--]]

local core = require "autofolder_core"
local settings = require "autofolder_settings"

local POLL_US = 300000      -- 300 ms, in microseconds
local SETTINGS_US = 1000000 -- how often the settings file is read: 1 s
local PREFIX = "[autofolder] "

local NONE = {} -- "no text": unlike nil, which means "no file"
local sort_order = settings.ORDERS[1].id -- from the settings file
local settings_text = NONE  -- the settings file's text applied last (nil: no file)
local settings_new = NONE   -- a changed text read once, applied when the next read gives it again
local settings_at = nil     -- when the file was read last (vlc.misc.mdate); nil: never
local settings_unreadable = false -- whether the last read failed (warned once)

local active_folder = nil -- path key of the folder built last
local active_path = nil   -- its path, for the log
local active_files = nil  -- its files ({ name, mtime, id, ... }) at the build, for a re-sort
local managed = {}        -- id -> true for the items of that folder this script added, and the file opened there
local readded = {}        -- id -> true for the user's own items this script added again (never "just opened")
local last_id = -1        -- the playing item's id at the previous poll
local started_max = 0     -- the highest id in the playlist when the playing item started
local played_any = false  -- whether an item has started since this script started
local tail_id = -1        -- the playlist's last item
local tail_since = 0      -- since when (vlc.misc.mdate) it has been the last item

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

local function max_id(items)
    local last = 0
    for _, item in ipairs(items) do
        last = math.max(last, item.id)
    end
    return last
end

-- Enqueues the files ({ path, ... }) in one call, in order (they are appended),
-- marks the new items as managed and sets each file's `id`. Returns how many
-- were added.
local function enqueue(files)
    if #files == 0 then
        return 0
    end
    -- New items get higher ids than every item before them (measured).
    local last = max_id(playlist_items())
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

-- Deletes the items `ids`, never the playing one. For an id that is gone
-- already, delete returns -1; ids come from a counter that only grows (3.0
-- source), so an old id never names a new item. Returns how many were deleted.
local function delete(ids)
    local playing = vlc.playlist.current()
    local count = 0
    for _, id in ipairs(ids) do
        if id ~= playing and vlc.playlist.delete(id) == 0 then
            count = count + 1
        end
        managed[id] = nil
    end
    return count
end

-- The playlist's item ids, in order.
local function playlist_ids()
    local ids = {}
    for i, item in ipairs(playlist_items()) do
        ids[i] = item.id
    end
    return ids
end

-- The ids of the files ({ id, ... }) that have one, in the files' order.
local function ids_of(files)
    local ids = {}
    for _, file in ipairs(files) do
        if file.id then
            ids[#ids + 1] = file.id
        end
    end
    return ids
end

-- Puts the playlist in the order `target` (ids, as core.target_order gives
-- them; ids no longer in the playlist are left out) with the fewest moves.
-- Moves only to the front of the playlist node: VLC 3.0's move after an item
-- is broken (docs/decisions.md). Returns the number of moves.
local function reorder(target)
    local node = vlc.playlist.get("playlist")
    local current, present = {}, {}
    for i, item in ipairs(node.children or {}) do
        current[i] = item.id
        present[item.id] = true
    end
    local wanted = {}
    for _, id in ipairs(target) do
        if present[id] then
            wanted[#wanted + 1] = id
        end
    end
    local moves = core.front_moves(current, wanted)
    for _, id in ipairs(moves) do
        if vlc.playlist.move(id, node.id) ~= 0 then
            warn("cannot move item " .. id .. " (removed meanwhile?)")
        end
    end
    return #moves
end

-- Puts the folder's files ({ id, path, ... } in sort order) together, in
-- that order, where the playing item is (if it's one of them; otherwise where
-- the folder's first item is), with the user's own items in their order around
-- them (core.target_order). Files with no id are added; a file whose item is
-- gone (the user deleted it) stays out.
-- VLC 3.0's playlist window doesn't show a move of an item it already shows,
-- but it shows items deleted and added, each at its index in the playlist when
-- it handles the event (research/vlc-lua-api.md). So the items that would
-- change their order are deleted first and added again with the new files, in
-- one enqueue in sort order, before the moves; the others keep their order
-- (core.keep_in_order). Never added again: the playing item (it would
-- restart) and the user's items outside the folder. An item added again stays
-- this script's, or the user's. The target is worked out before anything is
-- deleted, so the folder keeps its place also when none of its items stays.
-- Returns the number of files added, of items added again, and of moves.
local function place(files)
    local current = playlist_ids()
    local present = {}
    for _, id in ipairs(current) do
        present[id] = true
    end
    local folder_ids, in_folder = {}, {}
    for _, file in ipairs(files) do
        if file.id and present[file.id] then
            folder_ids[#folder_ids + 1] = file.id
            in_folder[file.id] = true
        end
    end
    local playing = vlc.playlist.current()
    local target, before, after = core.target_order(current, folder_ids, playing)
    local fixed = {}
    for _, id in ipairs(current) do
        fixed[id] = id == playing or not in_folder[id]
    end
    local keep = core.keep_in_order(current, target, fixed)

    local old_ids, again, users, new = {}, {}, {}, {}
    for _, file in ipairs(files) do
        if file.id and present[file.id] and not keep[file.id] then
            old_ids[#old_ids + 1] = file.id
            again[#again + 1] = file
            users[file] = not managed[file.id]
            file.id = nil
        end
        if not file.id then
            new[#new + 1] = file
        end
    end
    delete(old_ids)
    local count = enqueue(new)
    local count_again = 0
    for _, file in ipairs(again) do
        if file.id then
            count_again = count_again + 1
            if users[file] then
                managed[file.id] = nil
                readded[file.id] = true
            end
        end
    end

    local wanted = before
    for _, id in ipairs(ids_of(files)) do
        wanted[#wanted + 1] = id
    end
    for _, id in ipairs(after) do
        wanted[#wanted + 1] = id
    end
    return count - count_again, count_again, reorder(wanted)
end

-- Removes the items of the active folder that this script added, and the file
-- opened there; the user's own items stay.
local function leave_folder()
    local ids = {}
    for id in pairs(managed) do
        ids[#ids + 1] = id
    end
    local count = delete(ids)
    info(string.format("left folder %s: removed %d items", active_path, count))
    managed = {}
end

local function file_exists(path)
    return vlc.net.stat(path) ~= nil
end

-- Builds the folder of the file just opened (the item `id`, path `path`): adds
-- its other videos, removes extra copies and items whose file is gone, and puts
-- the folder in sort order where its first item is.
local function build(path, id)
    local folder, name = core.split_path(path)
    local start = vlc.misc.mdate()
    -- The scan doesn't wait (no mwait), so catching its errors is safe.
    local ok, files = pcall(core.scan_folder, folder)
    local scanned = vlc.misc.mdate()
    if not ok then
        -- Not retried (docs/decisions.md): opening the file again builds it.
        warn(string.format("cannot read the folder %s after %.0f ms: %s (open the file again to retry)",
            folder, (scanned - start) / 1000, tostring(files)))
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
    core.sort_files(files, sort_order)

    local remove = core.match_items(playlist_items(), folder, files, id, file_exists)
    if playing.id ~= id then
        warn("the playing item is not in the playlist any more: " .. path)
        return
    end
    -- A file that was the user's own item stays theirs when another copy of
    -- it is kept (the re-opened one, or the first): it isn't removed on a
    -- folder switch.
    local own = {}
    for _, file in ipairs(files) do
        for _, copy in ipairs(file.copies or {}) do
            if not managed[copy] then
                own[file.id] = true
            end
        end
    end

    local folder_key = core.path_key(folder)
    if active_folder and active_folder ~= folder_key then
        leave_folder()
    end
    active_folder, active_path = folder_key, folder
    local removed = delete(remove)
    -- Forget items that are gone (e.g. the playlist was cleared).
    local still = {}
    for _, item in ipairs(playlist_items()) do
        still[item.id] = managed[item.id]
    end
    managed = still
    managed[id] = true -- the file opened here goes with the folder on a switch
    for file_id in pairs(own) do
        managed[file_id] = nil
    end

    active_files = files
    -- The opened item plays, so the folder goes where it is: at the end.
    local added, again, moves = place(files)

    local folder_ids, before = ids_of(files), 0
    for i, file_id in ipairs(folder_ids) do
        if file_id == playing.id then
            before = i - 1
        end
    end
    local after = #folder_ids - 1 - before
    -- The time shows whether a slow share is the cause when the folder comes late.
    info(string.format("folder %s: %d videos, %d before and %d after %s; added %d, re-added %d, removed %d;"
        .. " %d moves; %.0f ms (scan %.0f ms)", folder, #files, before, after, name, added, again, removed,
        moves, (vlc.misc.mdate() - start) / 1000, (scanned - start) / 1000))
end

-- Puts the active folder's items in the sort order `order`, after the order
-- changed (place: only the items that must move are added again). It only
-- reorders, by the names and dates of the build: adding and removing files,
-- and a file changed since, wait for the next file opened. Items removed
-- meanwhile stay removed.
local function resort(order)
    if not active_files then
        return
    end
    core.sort_files(active_files, order)
    -- Only files that have an item: one whose enqueue found no item (warned)
    -- would otherwise be added again on every change.
    local with_item = {}
    for _, file in ipairs(active_files) do
        if file.id then
            with_item[#with_item + 1] = file
        end
    end
    local _, again, moves = place(with_item)
    info(string.format("folder %s: re-sorted by %s; re-added %d items; %d moves", active_path, order, again, moves))
end

-- Applies the settings file's text (nil: no file): the video types for the
-- next build, a new sort order at once. Remembers the text only when all of
-- it worked, so an error is retried at the next read.
local function apply_settings(text, path)
    local values, warnings = settings.parse(text or "")
    for _, message in ipairs(warnings) do
        warn(settings.FILE_NAME .. " " .. message)
    end
    core.set_extensions(values.extensions)
    info(string.format("settings: sort %s; video types %s (%s %s)", values.sort,
        table.concat(values.extensions, " "), text and "from" or "defaults: no file", path))
    if values.sort ~= sort_order then
        resort(values.sort)
        sort_order = values.sort
    end
    settings_text = text
end

-- Reads the settings file, at most once per SETTINGS_US, and applies a
-- change. The text is compared, not the file's time: stat's times count whole
-- seconds. A changed text is applied when the next read gives it again, so a
-- file read while it is being written is never applied. The first read is
-- applied at once, so the first build uses it.
local function check_settings()
    local now = vlc.misc.mdate()
    if settings_at and now - settings_at < SETTINGS_US then
        return
    end
    local first = settings_at == nil
    settings_at = now
    local path = settings.path()
    local text = settings.read(path)
    if text == false then
        if not settings_unreadable then
            settings_unreadable = true
            warn("cannot read " .. path .. "; keeping the settings read before (at start: the defaults)")
        end
        return -- try again at the next read
    end
    settings_unreadable = false
    if text == settings_text then
        settings_new = NONE
    elseif first or text == settings_new then
        settings_new = NONE
        apply_settings(text, path)
    else
        settings_new = text
    end
end

-- Called when the file `id` was just opened.
local function on_opened(id)
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
    build(path, id)
end

local function poll()
    -- current() first: an item that plays is already in the playlist.
    local id = vlc.playlist.current()
    local items = playlist_items()
    local tail = items[#items]
    if (tail and tail.id or -1) ~= tail_id then
        tail_id, tail_since = tail and tail.id or -1, vlc.misc.mdate()
    end
    if id == last_id then
        return
    end
    last_id = id -- set first, so a failing item isn't retried on every poll
    if id == -1 then
        -- No current item (e.g. after clear(); stop() keeps it): the next
        -- item is judged against the one before.
        return
    end

    local first_play = not played_any
    played_any = true
    local previous_max = started_max
    started_max = max_id(items)
    if managed[id] or readded[id] then
        -- An item this script added (or added again: it can be the last item,
        -- added seconds ago): clicked, or reached with Next/Previous.
        return
    end
    local opened, reason = core.just_opened(id, tail_id, previous_max,
        (vlc.misc.mdate() - tail_since) / 1000000, first_play)
    if not opened then
        dbg("item " .. id .. " started, no build: " .. reason)
        return
    end
    -- The items the build adds are managed, so they never build (above).
    on_opened(id)
end

local STEPS = { check_settings, poll } -- run in this order on every poll

info("started")

-- Never wrap mwait in pcall: when VLC closes, mwait raises "Interrupted.",
-- and that error must end this script, or VLC can hang on close.
while true do
    -- A bug in one poll is logged and doesn't stop the script. Neither
    -- function waits, so these pcalls can't catch the "Interrupted." of VLC
    -- closing. The settings come first, so the first build uses them; a bug
    -- there doesn't stop the builds.
    for _, step in ipairs(STEPS) do
        local ok, err = pcall(step)
        if not ok then
            vlc.msg.err(PREFIX .. tostring(err))
        end
    end
    vlc.misc.mwait(vlc.misc.mdate() + POLL_US)
end
