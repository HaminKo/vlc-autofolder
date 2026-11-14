--[[
vlc-autofolder settings dialog (View > Auto Folder Playlist settings): the
sort order and the video types, saved to autofolder.ini (see
lua\modules\autofolder_settings.lua). The interface script
lua\intf\autofolder.lua reads that file about every second, so a change
applies without restarting VLC.

VLC 3.0 runs this file twice (research/vlc-lua-api.md, "Extensions and
dialogs"):
- at startup, in a bare Lua state (no libraries, no vlc table, a require that
  returns nothing), only to call descriptor(). So the top level only defines
  functions.
- at each activation, in a fresh state with everything. Deactivation closes
  that state, so every opening reads the file again.
Tests: tests\lua\intf\test_dialog.lua (with a stand-in for VLC's dialog API).
--]]

local settings = require "autofolder_settings" -- nil during the startup scan

local PREFIX = "[autofolder] dialog: "

local dlg         -- the dialog while the extension is active
local sort_input  -- its widgets
local types_input
local note

function descriptor()
    return {
        title = "Auto Folder Playlist settings",
        version = "0.1.0",
        author = "vlc-autofolder",
        shortdesc = "Auto Folder Playlist settings",
        description = "The sort order and the video file types for the autofolder"
            .. " interface script, which adds the other videos of an opened file's"
            .. " folder to the playlist.",
        capabilities = {},
    }
end

-- Text for a label: VLC's Qt labels show rich text, so <, > and & need
-- escaping, and a line break is <br>.
local function label_text(text)
    return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\n", "<br>"))
end

local function set_note(text, is_error)
    text = label_text(text)
    if is_error then
        text = '<span style="color:#c00000">' .. text .. "</span>"
    end
    note:set_text(text)
end

-- The sort order whose field `key` ("id" or "label") is `value`.
local function find_order(key, value)
    for _, order in ipairs(settings.ORDERS) do
        if order[key] == value then
            return order
        end
    end
end

local function save()
    local list, bad = settings.parse_extensions(types_input:get_text() or "")
    if #bad > 0 then
        set_note('Not a file type: "' .. table.concat(bad, '", "')
            .. '". Use letters and digits only, separated by spaces, e.g. mp4 mkv.', true)
        return
    end
    if #list == 0 then
        list = settings.defaults().extensions
    end
    -- get_text, not get_value: after set_text, VLC 3.0's get_value gives the
    -- first entry until the user picks another one.
    local order = find_order("label", sort_input:get_text())
    if not order then
        set_note("Pick a sort order.", true)
        return
    end
    local sort = order.id
    local ok, err = settings.write({ sort = sort, extensions = list })
    if not ok then
        set_note("Not saved: " .. err .. ".", true)
        return
    end
    vlc.msg.info(PREFIX .. "saved sort " .. sort .. "; video types " .. table.concat(list, " "))
    vlc.deactivate()
end

local function cancel()
    vlc.deactivate()
end

function activate()
    local values, notes = settings.defaults(), {}
    local path = settings.path()
    local text = settings.read(path)
    if text == false then
        notes[1] = "Cannot read " .. path .. ": showing the defaults."
    elseif text then
        local warnings
        values, warnings = settings.parse(text)
        for i, message in ipairs(warnings) do
            notes[i] = settings.FILE_NAME .. " " .. message
        end
        if #notes > 0 then
            notes[#notes + 1] = "Save rewrites the file with the values shown."
        end
    end

    dlg = vlc.dialog("Auto Folder Playlist")
    dlg:add_label("Sort order:", 1, 1, 1, 1)
    sort_input = dlg:add_dropdown(2, 1, 2, 1)
    for i, order in ipairs(settings.ORDERS) do
        sort_input:add_value(order.label, i)
    end
    sort_input:set_text(find_order("id", values.sort).label)
    dlg:add_label("Video types:", 1, 2, 1, 1)
    types_input = dlg:add_text_input(table.concat(values.extensions, " "), 2, 2, 2, 1)
    dlg:add_label(label_text("Separated by spaces. Empty for the default list:\n"
        .. table.concat(settings.DEFAULT_EXTENSIONS, " ")), 2, 3, 2, 1)
    note = dlg:add_label("", 1, 4, 3, 1)
    if #notes > 0 then
        set_note(table.concat(notes, "\n"), false)
    end
    dlg:add_button("Save", save, 2, 5, 1, 1)
    dlg:add_button("Cancel", cancel, 3, 5, 1, 1)
    dlg:show()
end

-- The dialog's window was closed (X or Escape).
function close()
    vlc.deactivate()
end

function deactivate()
    if dlg then
        dlg:delete()
        dlg = nil
    end
end
