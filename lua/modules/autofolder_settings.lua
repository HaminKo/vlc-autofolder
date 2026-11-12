--[[
The settings of vlc-autofolder: the file autofolder.ini in VLC's user folder
(vlc.config.userdatadir(): %APPDATA%\vlc, or the portable folder). Used by the
interface script (lua\intf\autofolder.lua) and the dialog (lua\extensions\,
To do 3 step B). It lives in lua\modules\, where VLC looks for modules of both
kinds of script. Load with:
    local settings = require "autofolder_settings"
Tests: tests\lua\intf\test_settings.lua.

The file has one setting per line; # or ; starts a comment, on its own line
or after a value:
    sort=name-az   # my choice
    extensions=mp4 mkv avi
Keys and values ignore case and spaces around "=". A missing line gives that
setting's default; a wrong value gives the default and a warning.
--]]

local M = {}

M.FILE_NAME = "autofolder.ini"

-- The sort orders: id (the value in the file) and label (for the dialog). The
-- first is the default.
M.ORDERS = {
    { id = "date-oldest", label = "Date modified, oldest first" },
    { id = "date-newest", label = "Date modified, newest first" },
    { id = "name-az", label = "Name, A to Z" },
    { id = "name-za", label = "Name, Z to A" },
}

-- The file extensions that count as video by default, lower case.
M.DEFAULT_EXTENSIONS = {
    "mp4", "mkv", "avi", "mov", "wmv", "webm", "m4v", "flv", "ts", "mpg", "mpeg",
    "m2ts", "mts", "3gp", "ogv", "vob",
}

local order_ids = {}
local order_list = {}
for i, order in ipairs(M.ORDERS) do
    order_ids[order.id] = true
    order_list[i] = order.id
end

-- Lower-cases ASCII letters only (string.lower depends on the C locale).
local function ascii_lower(s)
    return (s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end))
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The default settings: { sort = "date-oldest", extensions = { "mp4", ... } }
-- (a new table each time).
function M.defaults()
    local list = {}
    for i, ext in ipairs(M.DEFAULT_EXTENSIONS) do
        list[i] = ext
    end
    return { sort = M.ORDERS[1].id, extensions = list }
end

-- A list of extensions from text such as "mp4, .MKV *.avi": separated by spaces
-- or commas, with or without a leading "." or "*.", any case. Returns the list
-- (lower case, each once) and the words that aren't extensions (only ASCII
-- letters and digits are).
function M.parse_extensions(text)
    local list, seen, bad = {}, {}, {}
    for word in text:gmatch("[^%s,]+") do
        local ext = ascii_lower((word:gsub("^%*?%.", "")))
        if not ext:match("^[0-9a-z]+$") then
            bad[#bad + 1] = word
        elseif not seen[ext] then
            seen[ext] = true
            list[#list + 1] = ext
        end
    end
    return list, bad
end

-- The settings in a file's text. Returns the settings (as defaults() gives
-- them) and a list of warnings ("line 2: ..."), each for something that was
-- ignored.
function M.parse(text)
    local result, warnings = M.defaults(), {}
    local function warn(n, message)
        warnings[#warnings + 1] = "line " .. n .. ": " .. message
    end
    text = text:gsub("^\239\187\191", "") -- a UTF-8 BOM (Notepad may write one)
    local n = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        line = trim(line) -- also drops the \r of Windows line ends
        if line ~= "" and not line:match("^[#;]") then
            local key, value = line:match("^([^=]*)=(.*)$")
            key = key and ascii_lower(trim(key))
            -- No value has a # or ;, so from there on it's a comment.
            value = value and trim((value:gsub("[#;].*$", "")))
            if key == "sort" then
                local id = ascii_lower(value)
                if order_ids[id] then
                    result.sort = id
                else
                    warn(n, string.format('unknown sort order "%s" (one of: %s); using %s',
                        value, table.concat(order_list, ", "), result.sort))
                end
            elseif key == "extensions" then
                local list, bad = M.parse_extensions(value)
                if #bad > 0 then
                    warn(n, 'not a file extension, ignored: "' .. table.concat(bad, '", "') .. '"')
                end
                -- An empty list means the default list.
                result.extensions = #list > 0 and list or M.defaults().extensions
            else
                warn(n, 'not a setting, ignored: "' .. line .. '"')
            end
        end
    end
    return result, warnings
end

-- The text of a settings file with these settings (Windows line ends).
function M.format(values)
    return table.concat({
        "# vlc-autofolder settings. While VLC runs, a change applies within about two seconds.",
        "# sort: " .. table.concat(order_list, ", "),
        "sort=" .. values.sort,
        "# extensions: the file types that count as video, separated by spaces",
        "extensions=" .. table.concat(values.extensions, " "),
        "",
    }, "\r\n")
end

-- The settings file's path.
function M.path()
    return (vlc.config.userdatadir():gsub("[\\/]+$", "")) .. "\\" .. M.FILE_NAME
end

-- The text of the settings file (path: M.path() if nil). Returns nil when the
-- file doesn't exist, and false when it exists but can't be read (e.g. while
-- another program writes it).
function M.read(path)
    path = path or M.path()
    -- On failure vlc.io.open returns no value at all, not nil and a message.
    local file = vlc.io.open(path, "rb")
    if not file then
        if vlc.net.stat(path) then
            return false
        end
        return nil
    end
    local text = file:read("*a")
    file:close()
    return text or ""
end

-- Writes the settings to the file (path: M.path() if nil) in one write.
-- Returns true, or nil and a message.
function M.write(values, path)
    path = path or M.path()
    local file = vlc.io.open(path, "wb")
    if not file then
        return nil, "cannot write " .. path
    end
    -- write gives false when nothing was written; a failure inside close
    -- (e.g. a full disk) can't be seen: close returns nothing.
    local ok = file:write(M.format(values))
    file:close()
    if not ok then
        return nil, "cannot write " .. path
    end
    return true
end

return M
