--[[
API spike (To do 1 step B): the vlc.net, vlc.io and vlc.strings facts the
folder logic relies on.
run-tests.ps1 starts it with every test video and one UNC path to a video on
VLC's command line, so the playlist holds the URIs VLC makes itself.
"info" lines record measurements (written up in research/vlc-lua-api.md);
ok/fail lines check what later code relies on.
--]]

local t = require "testlib"

local CAFE = "caf\195\169.mkv" -- UTF-8 bytes; Lua 5.1 has no \x escapes
local VIDEO_SIZE = 185080 -- bytes, the generated test video

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end

-- A file URI back to a Windows path, UNC included (vlc.strings.make_path drops
-- the server localhost; see below). nil for other URIs.
local function uri_to_path(uri)
    local decoded = vlc.strings.decode_uri(uri)
    local rest = decoded:match("^file:///(.*)$")
    if rest then
        return (rest:gsub("/", "\\"))
    end
    rest = decoded:match("^file://(.*)$") -- file://server/share/...
    if rest then
        return "\\\\" .. (rest:gsub("/", "\\"))
    end
    return nil
end

-- Finds an item by URI anywhere in the playlist tree.
local function find_item(node, uri)
    for _, item in ipairs(node.children or {}) do
        if item.path == uri then
            return item
        end
        local found = find_item(item, uri)
        if found then
            return found
        end
    end
    return nil
end

local function describe(value)
    if type(value) ~= "table" then
        return tostring(value)
    end
    local keys = {}
    for k in pairs(value) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = k .. "=" .. tostring(value[k])
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

t.run(function()
    local media = config.media
    local videos = t.read_lines(config.videos)
    t.equal("videos.txt lists the 17 test videos", #videos, 17)

    -- Which functions exist in an interface script.
    local present = {}
    for _, name in ipairs({ "net.stat", "net.opendir", "io.readdir", "strings.url_parse",
        "strings.make_path", "var.add_callback", "misc.should_die", "playlist.move" }) do
        local ns, fn = name:match("^(%w+)%.([%w_]+)$")
        present[#present + 1] = name .. "=" .. type(vlc[ns] and vlc[ns][fn])
    end
    t.info("functions: " .. table.concat(present, ", "))
    t.check("vlc.net.stat and opendir are functions",
        type(vlc.net.stat) == "function" and type(vlc.net.opendir) == "function")

    -- opendir
    local entries = vlc.net.opendir(media)
    t.info("opendir: " .. #entries .. " entries; '.': " .. tostring(contains(entries, "."))
        .. ", '..': " .. tostring(contains(entries, "..")) .. "; first: " .. tostring(entries[1]))
    local missing = {}
    for _, name in ipairs(videos) do
        if not contains(entries, name) then
            missing[#missing + 1] = name
        end
    end
    t.check("opendir lists every video, Unicode and hidden ones too", #missing == 0,
        "missing: " .. table.concat(missing, " | "))
    t.check("opendir lists the subfolder", contains(entries, "Season 2"))
    local ok_fwd, fwd = pcall(vlc.net.opendir, (media:gsub("\\", "/")))
    t.info("opendir with / separators: " .. (ok_fwd and (#fwd .. " entries") or tostring(fwd)))
    local ok_missing, missing_err = pcall(vlc.net.opendir, media .. "\\no such folder")
    t.info("opendir on a missing folder: "
        .. (ok_missing and ("returns " .. describe(missing_err)) or ("raises: " .. tostring(missing_err))))
    if type(vlc.io.readdir) == "function" then
        local ok_rd, rd = pcall(vlc.io.readdir, media)
        t.info("io.readdir: " .. (ok_rd and (#rd .. " entries; '.': " .. tostring(contains(rd, "."))) or tostring(rd)))
    end

    -- stat: dates, sizes, Unicode, folders, missing paths
    local first = os.time({ year = 2026, month = 1, day = 1, hour = 12, min = 0, sec = 0 })
    local bad = {}
    for i, name in ipairs(videos) do
        local st = vlc.net.stat(media .. "\\" .. name)
        local want = first + (i - 1) * 3600
        if not st then
            bad[#bad + 1] = name .. ": nil"
        elseif st.type ~= "file" or st.size ~= VIDEO_SIZE or st.modification_time ~= want then
            bad[#bad + 1] = name .. ": " .. describe(st) .. " (want mtime " .. want .. ")"
        end
    end
    t.check("stat gives type, size and mtime for every video, Unicode too", #bad == 0, table.concat(bad, " | "))
    t.info("stat Episode 1.mkv: " .. describe(vlc.net.stat(media .. "\\Episode 1.mkv")))
    local summer = vlc.net.stat(media:match("^(.*)\\[^\\]+$") .. "\\summer.mkv")
    local summer_want = os.time({ year = 2026, month = 7, day = 1, hour = 12, min = 0, sec = 0 })
    t.info("stat summer.mkv (2026-07-01 12:00 local): mtime - expected = "
        .. tostring(summer and (summer.modification_time - summer_want)) .. " s")
    t.equal("stat on the folder", (vlc.net.stat(media) or {}).type, "dir")
    t.info("stat on the folder with a trailing backslash: " .. describe(vlc.net.stat(media .. "\\")))
    t.equal("stat on a missing file returns nil", vlc.net.stat(media .. "\\no such file.mkv"), nil)
    local normal = vlc.net.stat(media .. "\\Episode 1.mkv")
    local hidden = vlc.net.stat(media .. "\\attribute-hidden.mkv")
    t.info(string.format("stat mode: normal file %o, hidden-attribute file %o", normal.mode, hidden.mode))

    -- Plain Lua io.open on a non-ASCII name
    local plain = io.open(media .. "\\" .. CAFE, "rb")
    t.info("plain io.open on " .. CAFE .. ": " .. (plain and "opens" or "fails"))
    if plain then
        plain:close()
    end
    local vio = vlc.io.open(media .. "\\" .. CAFE, "rb")
    t.check("vlc.io.open opens a non-ASCII name", vio ~= nil)
    if vio then
        vio:close()
    end

    -- make_uri against the URIs VLC made for the command-line files
    local want_items = #videos + 1
    t.wait_for(function() return #t.playlist_items() >= want_items end, 5)
    local by_path = {}
    for _, item in ipairs(t.playlist_items()) do
        by_path[item.path] = item
    end
    local mismatched, encoded, round_trip = {}, {}, {}
    for _, name in ipairs(videos) do
        local path = media .. "\\" .. name
        local uri = vlc.strings.make_uri(path)
        encoded[#encoded + 1] = uri:match("[^/]*$")
        if not by_path[uri] then
            mismatched[#mismatched + 1] = uri
        end
        if uri_to_path(uri) ~= path then
            round_trip[#round_trip + 1] = name .. " -> " .. tostring(uri_to_path(uri))
        end
    end
    t.info("make_uri file names: " .. table.concat(encoded, " | "))
    t.info("make_uri folder: " .. vlc.strings.make_uri(media))
    t.check("make_uri matches VLC's own URI for every video", #mismatched == 0,
        "not in the playlist: " .. table.concat(mismatched, " | "))
    t.check("decoding make_uri gives back the path", #round_trip == 0, table.concat(round_trip, " | "))
    -- make_path: not in the 3.0 README, but present in 3.0.24.
    local make_path_wrong = {}
    for _, name in ipairs(videos) do
        local path = media .. "\\" .. name
        local back = vlc.strings.make_path(vlc.strings.make_uri(path))
        if back ~= path then
            make_path_wrong[#make_path_wrong + 1] = path .. " -> " .. tostring(back)
        end
    end
    t.check("make_path gives back every local path", #make_path_wrong == 0, table.concat(make_path_wrong, " | "))
    local unc_file = config.unc .. "\\Episode 1.mkv"
    local unc_back = vlc.strings.make_path(vlc.strings.make_uri(unc_file))
    t.equal("make_path keeps the server of a UNC path", unc_back, unc_file)
    -- The server "localhost" counts as this PC: make_path drops it, and VLC
    -- can't open such a file either (measured 2026-11-11, To do 2 step D).
    local localhost_file = unc_file:gsub("^\\\\[^\\]+\\", "\\\\localhost\\")
    t.equal("make_path drops the server localhost",
        vlc.strings.make_path(vlc.strings.make_uri(localhost_file)), (unc_file:gsub("^\\\\[^\\]+\\", "")))

    -- UNC
    local unc_uri = vlc.strings.make_uri(unc_file)
    t.info("make_uri UNC: " .. unc_uri)
    t.check("make_uri matches VLC's own URI for a UNC path", by_path[unc_uri] ~= nil, "not in the playlist")
    t.equal("decoding the UNC URI gives back the path", uri_to_path(unc_uri), unc_file)
    t.info("url_parse UNC: " .. describe(vlc.strings.url_parse(unc_uri)))
    local unc_dir = vlc.net.stat(config.unc)
    if not unc_dir then
        t.info("UNC folder " .. config.unc .. " not reachable: stat/opendir checks skipped")
    else
        t.equal("stat on a UNC folder", unc_dir.type, "dir")
        local ok_unc, unc_entries = pcall(vlc.net.opendir, config.unc)
        t.check("opendir on a UNC folder", ok_unc and contains(unc_entries, CAFE), tostring(unc_entries))
        t.equal("stat mtime is the same through UNC", (vlc.net.stat(unc_file) or {}).modification_time,
            normal.modification_time)
    end

    -- The URIs VLC makes when it expands an opened folder. Playing a folder item
    -- replaces it with the folder's entries (and a played subfolder with its own).
    local folder_uri = vlc.strings.make_uri(media)
    local old = {}
    for _, item in ipairs(t.playlist_items()) do
        old[item.id] = true
    end
    local function new_items()
        local list = {}
        for _, item in ipairs(t.playlist_items()) do
            if not old[item.id] then
                list[#list + 1] = item
            end
        end
        return list
    end
    vlc.playlist.add({ { path = folder_uri } })
    local expanded = t.wait_for(function()
        local list = new_items()
        return #list > 1 and not find_item(vlc.playlist.get("playlist"), folder_uri)
    end, 5)
    t.sleep(1) -- let the subfolder that starts playing expand too
    if t.check("an opened folder is replaced by its entries", expanded,
        "new items after 5 s: " .. #new_items()) then
        local names, differ = {}, {}
        for _, item in ipairs(new_items()) do
            local path = uri_to_path(item.path)
            if not path then
                names[#names + 1] = item.path
                differ[#differ + 1] = item.path .. " is not a file URI"
            else
                local under_media = path:sub(1, #media + 1) == media .. "\\"
                names[#names + 1] = (under_media and path:sub(#media + 2) or path)
                    .. (item.children and " (node)" or "")
                local canonical = vlc.strings.make_uri(path)
                if item.path ~= canonical then
                    differ[#differ + 1] = item.path .. " vs " .. canonical
                end
            end
        end
        t.info("folder entries in the playlist: " .. table.concat(names, " | "))
        t.check("VLC's folder entry URIs match make_uri", #differ == 0, table.concat(differ, " | "))
    end
end)
