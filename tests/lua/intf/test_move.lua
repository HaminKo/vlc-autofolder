--[[
API spike (To do 1 step B): moving items around the playing one.
run-tests.ps1 starts it with "episode 3.MP4" on VLC's command line.

VLC 3.0's playlist.move(id, target) has two cases (modules/lua/libs/playlist.c):
- target is a node (such as the playlist node): the item becomes its first
  child. This works.
- target is an item: the new index is computed from item ids,
  target.id - first_child.id + 1, not from the target's position. The item
  lands in the wrong place, and an index out of range crashes VLC (measured
  2026-11-11: index -1 gave an access violation).
So the folder logic only moves items to the front of the playlist node: files
after the playing one are enqueued in order (appended), files before it are
enqueued and then moved to the front one by one, last first. This test checks
that pattern, then shows the id formula with an index that is in range.
--]]

local t = require "testlib"

local function uri(name)
    return vlc.strings.make_uri(config.media .. "\\" .. name)
end

-- Waits until the playing input's time passes `seconds`; returns the time in microseconds.
local function played_past(seconds)
    t.wait_for(function() return t.input_time() > seconds * 1000000 end, 5)
    return t.input_time()
end

local names = {} -- id -> file name, for messages

-- Calls a playlist action, then checks that `want_id` becomes the playing item.
local function step(label, action, want_id)
    action()
    local ok = t.wait_for(function() return vlc.playlist.current() == want_id end, 5)
    t.check(label, ok, "playing: " .. tostring(names[vlc.playlist.current()]))
end

-- Runs fn and checks that playback carries on: the same item plays and its time
-- did not go back. It has played 1.5 s first, so a restart (time near 0) shows.
local function keeps_playing(label, fn)
    local id = vlc.playlist.current()
    local before = played_past(1.5)
    fn()
    t.equal(label .. ": the same item plays", vlc.playlist.current(), id)
    t.sleep(0.3)
    local after = t.input_time()
    t.check(label .. ": playback not restarted", after >= before,
        string.format("time %.2f s before, %.2f s after", before / 1e6, after / 1e6))
end

local function playlist_ids()
    local ids = {}
    for _, item in ipairs(t.playlist_items()) do
        ids[#ids + 1] = item.id
    end
    return ids
end

-- `ids` without `item`, and the 1-based position `item` had.
local function without(ids, item)
    local rest, from = {}, nil
    for i, id in ipairs(ids) do
        if id == item then
            from = i
        else
            rest[#rest + 1] = id
        end
    end
    return rest, from
end

-- The order VLC 3.0 makes for move(item, target) when target is an item: the id
-- formula, then playlist_TreeMove (remove the item, shift the index if the item
-- was before it, insert). Returns nil when the index is out of range (a crash).
local function id_formula_order(ids, item, target)
    local index = target - ids[1] + 1 -- 0-based, computed before the removal
    local rest, from = without(ids, item)
    if from - 1 < index then
        index = index - 1
    end
    if index < 0 or index > #rest then
        return nil
    end
    table.insert(rest, index + 1, item)
    return rest
end

-- The order a correct move(item, target) would make: item right after target.
local function intended_order(ids, item, target)
    local rest = without(ids, item)
    for i, id in ipairs(rest) do
        if id == target then
            table.insert(rest, i + 1, item)
            break
        end
    end
    return rest
end

t.run(function()
    local playing = t.wait_for(t.current_item, 5)
    if not t.check("episode 3 is playing", playing and playing.path == uri("episode 3.MP4"),
        playing and playing.path or "nothing after 5 s") then
        return
    end
    local id3 = playing.id

    -- One enqueue call in sort order, as the folder logic will make it.
    local added = vlc.playlist.enqueue({
        { path = uri("Episode 1.mkv") }, { path = uri("Episode 2.mkv") }, { path = uri("Episode 10.mkv") },
    })
    t.info("enqueue returned " .. tostring(added) .. "; order: " .. t.playlist_names())
    local by_name = {}
    for _, item in ipairs(t.playlist_items()) do
        by_name[t.file_name(item.path)] = item.id
        names[item.id] = t.file_name(item.path)
    end
    local id1, id2, id10 = by_name["Episode 1.mkv"], by_name["Episode 2.mkv"], by_name["Episode 10.mkv"]
    if not t.check("the enqueued items are found by URI", id1 and id2 and id10) then
        return
    end
    local node = vlc.playlist.get("playlist").id
    t.info("ids: playlist node " .. node .. ", e3 " .. id3 .. ", E1 " .. id1 .. ", E2 " .. id2 .. ", E10 " .. id10)

    -- The files before the playing one go to the front, last first.
    keeps_playing("moving two items to the front", function()
        local r2 = vlc.playlist.move(id2, node)
        local r1 = vlc.playlist.move(id1, node)
        t.info("move to the node returned " .. tostring(r2) .. ", " .. tostring(r1))
    end)
    t.equal("order after the moves", t.playlist_names(),
        "Episode 1.mkv | Episode 2.mkv | episode 3.MP4 | Episode 10.mkv")
    t.equal("move with a missing id returns -1", vlc.playlist.move(999999, node), -1)

    step("Next plays Episode 10", vlc.playlist.next, id10)
    step("Prev plays episode 3", vlc.playlist.prev, id3)
    step("Prev plays Episode 2", vlc.playlist.prev, id2)
    step("Prev plays Episode 1", vlc.playlist.prev, id1)
    step("Next plays Episode 2", vlc.playlist.next, id2)

    -- The playing item itself (To do 2: a re-opened duplicate is the playing one).
    keeps_playing("moving the playing item to the front", function()
        vlc.playlist.move(id2, node)
    end)
    t.equal("order after moving the playing item", t.playlist_names(),
        "Episode 2.mkv | Episode 1.mkv | episode 3.MP4 | Episode 10.mkv")
    step("Next from the moved item plays Episode 1", vlc.playlist.next, id1)

    -- The id formula, shown with the first move whose index is in range and whose
    -- result differs from "after target".
    local ids = playlist_ids()
    for _, item in ipairs(ids) do
        for _, target in ipairs(ids) do
            local predicted = item ~= target and id_formula_order(ids, item, target)
            local intended = predicted and intended_order(ids, item, target)
            if predicted and table.concat(predicted, ",") ~= table.concat(intended, ",") then
                vlc.playlist.move(item, target)
                t.info("move " .. names[item] .. " after " .. names[target] .. ": order became "
                    .. t.playlist_names())
                t.equal("move after an item follows the id formula, not the position",
                    table.concat(playlist_ids(), ","), table.concat(predicted, ","))
                return
            end
        end
    end
    t.info("no safe move shows the id formula with these ids")
end)
