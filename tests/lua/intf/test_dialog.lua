--[[
The settings dialog (To do 3 step B, lua\extensions\autofolder_dialog.lua).
The real dialog needs VLC's Qt interface, so this driver runs the extension
with a stand-in for VLC's dialog API that copies what VLC 3.0.24's source
does (research/vlc-lua-api.md, "Extensions and dialogs"):
- The startup scan runs the file in a bare state (no libraries, a require
  that returns nothing) and calls only descriptor().
- Each activation runs the file in a fresh environment. When one of its
  functions returns, the dialog's new widgets are created; after a
  vlc.deactivate(), deactivate() is called and the state is dropped.
- A dropdown pre-set with set_text shows that entry, but get_value() gives
  the first entry until the user picks another one (picking the entry shown
  changes nothing).
run-tests.ps1 starts the case with no settings file; no autofolder, no file
playing.
--]]

local t = require "testlib"
local settings = require "autofolder_settings"

local SCRIPT = (vlc.config.userdatadir():gsub("[\\/]+$", "")) .. "\\lua\\extensions\\autofolder_dialog.lua"
local NAME = "=autofolder_dialog.lua" -- the chunk name in error messages

local function read_file(path)
    local file = vlc.io.open(path, "rb")
    if not file then
        error("cannot read " .. path, 0)
    end
    local text = file:read("*a")
    file:close()
    return text
end

-- Writes a file as a person would in Notepad.
local function write_file(path, text)
    local file = vlc.io.open(path, "wb")
    if not file then
        error("cannot write " .. path, 0)
    end
    file:write(text)
    file:close()
end

-- The stand-in widgets. Only the methods VLC 3.0 has, each refusing the
-- widget kinds VLC refuses.
local TEXT_KINDS = { label = true, button = true, html = true, text_input = true, dropdown = true }

local Widget = {}
Widget.__index = Widget

local function check_kind(widget, kinds, method)
    if not kinds[widget.kind] then
        error("method " .. method .. " not valid for this widget", 3)
    end
end

function Widget:set_text(text)
    check_kind(self, TEXT_KINDS, "set_text")
    if type(text) ~= "string" then
        error("widget:set_text usage: (text)", 2)
    end
    self.text = text
end

function Widget:get_text()
    check_kind(self, TEXT_KINDS, "get_text")
    return self.text
end

function Widget:add_value(text, id)
    check_kind(self, { dropdown = true }, "add_value")
    self.values[#self.values + 1] = { text = text, id = id or 0 }
    if #self.values == 1 then
        self.selected = 1 -- VLC marks the first value of a dropdown selected
    end
end

function Widget:get_value()
    check_kind(self, { dropdown = true }, "get_value")
    local value = self.values[self.selected or 0]
    if value then
        return value.id, value.text
    end
    return -1, nil
end

local Dialog = {}
Dialog.__index = Dialog

local function add(dialog, kind, text, col, row, extra)
    local widget = setmetatable({ kind = kind, text = text, col = col, row = row, values = {} }, Widget)
    for key, value in pairs(extra or {}) do
        widget[key] = value
    end
    dialog.widgets[#dialog.widgets + 1] = widget
    return widget
end

function Dialog:add_label(text, col, row)
    return add(self, "label", text, col, row)
end

function Dialog:add_text_input(text, col, row)
    return add(self, "text_input", text, col, row)
end

function Dialog:add_dropdown(col, row)
    return add(self, "dropdown", nil, col, row)
end

function Dialog:add_button(text, fn, col, row)
    if type(fn) ~= "function" then
        error("dialog:add_button usage: (text, func)", 2)
    end
    return add(self, "button", text, col, row, { fn = fn })
end

function Dialog:show()
    self.shown = true
end

function Dialog:delete()
    self.deleted = true
end

-- Calls one of the extension's functions as VLC does: then the shown dialog's
-- new widgets are created (a dropdown shows the entry with its text, as Qt's
-- findText, else the first), and a requested deactivation runs.
local function call(ext, fn)
    if not ext.active then
        error("the extension isn't active", 2)
    end
    fn()
    local dialog = ext.dialog
    if dialog and dialog.shown and not dialog.deleted then
        for _, widget in ipairs(dialog.widgets) do
            if not widget.created then
                widget.created = true
                if widget.kind == "dropdown" and #widget.values > 0 then
                    widget.shown = 1
                    for i, value in ipairs(widget.values) do
                        if value.text == widget.text then
                            widget.shown = i
                            break
                        end
                    end
                end
            end
        end
    end
    if ext.deactivating then
        ext.env.deactivate()
        ext.active = false
        if ext.dialog then
            ext.dialog.deleted = true -- VLC closes the state, which deletes the dialog
        end
    end
end

local source -- the extension's text

-- Activates the extension: a fresh environment, the file run, activate().
-- Unlike VLC's fresh state, require gives the driver's own module table, so
-- the test can point settings.path elsewhere (the module keeps no state).
local function activate()
    local ext = { active = true }
    local env = setmetatable({}, { __index = _G })
    env.vlc = setmetatable({
        dialog = function(title)
            if ext.dialog then
                error("Only one dialog allowed per extension!", 2)
            end
            ext.dialog = setmetatable({ title = title, widgets = {} }, Dialog)
            return ext.dialog
        end,
        deactivate = function()
            ext.deactivating = true
        end,
    }, { __index = vlc })
    local chunk = assert(loadstring(source, NAME))
    setfenv(chunk, env)
    chunk()
    ext.env = env
    call(ext, env.activate)
    return ext
end

-- The dialog's widget of this kind at col, row.
local function widget_at(ext, kind, col, row)
    for _, widget in ipairs(ext.dialog.widgets) do
        if widget.kind == kind and widget.col == col and widget.row == row then
            return widget
        end
    end
    error("no " .. kind .. " at column " .. col .. ", row " .. row, 2)
end

local function sort_input(ext)
    return widget_at(ext, "dropdown", 2, 1)
end

local function types_input(ext)
    return widget_at(ext, "text_input", 2, 2)
end

local function note(ext)
    return widget_at(ext, "label", 1, 4).text
end

-- What the user sees: { sort = the dropdown's entry, types, note }.
local function view(ext)
    local dropdown = sort_input(ext)
    local entry = dropdown.values[dropdown.shown or 0]
    return { sort = entry and entry.text, types = types_input(ext).text, note = note(ext) }
end

-- The user picks a dropdown entry. Qt syncs the selection and the text only
-- when the entry shown changes.
local function pick(dropdown, label)
    for i, value in ipairs(dropdown.values) do
        if value.text == label then
            if i ~= dropdown.shown then
                dropdown.shown, dropdown.selected, dropdown.text = i, i, label
            end
            return
        end
    end
    error("no entry " .. label, 2)
end

local function click(ext, caption)
    for _, widget in ipairs(ext.dialog.widgets) do
        if widget.kind == "button" and widget.text == caption then
            return call(ext, widget.fn)
        end
    end
    error("no button " .. caption, 2)
end

local function closed(label, ext)
    t.check(label .. ": the dialog closes", not ext.active and ext.dialog.deleted,
        "active " .. tostring(ext.active) .. ", deleted " .. tostring(ext.dialog.deleted))
end

local function still_open(label, ext)
    t.check(label .. ": the dialog stays open", ext.active and not ext.dialog.deleted)
end

local function has(label, text, part)
    t.check(label, text and text:find(part, 1, true), "no " .. part .. " in: " .. tostring(text))
end

local DEFAULT_LIST = table.concat(settings.DEFAULT_EXTENSIONS, " ")

t.run(function()
    source = read_file(SCRIPT)

    -- The startup scan: no globals but require, and no string methods (the
    -- string metatable belongs to the whole state, so it is emptied for the
    -- scan and put back before any check).
    local chunk = assert(loadstring(source, NAME))
    local bare = { require = function() end }
    setfenv(chunk, bare)
    local string_meta = getmetatable("")
    local string_methods = string_meta.__index
    string_meta.__index = nil
    local ok, err = pcall(chunk)
    local described, descriptor = pcall(bare.descriptor)
    string_meta.__index = string_methods
    t.check("scan: the top level runs without libraries", ok, err)
    ok = described
    if t.check("scan: descriptor() runs without libraries", ok and type(descriptor) == "table",
            tostring(descriptor)) then
        t.equal("scan: menu title", descriptor.title, "Auto Folder Playlist settings")
        t.equal("scan: capabilities", type(descriptor.capabilities), "table")
    end

    -- No settings file: the defaults; Cancel writes nothing.
    t.equal("no settings file at the start", settings.read(), nil)
    local ext = activate()
    local shown = view(ext)
    t.equal("no file: dialog title", ext.dialog.title, "Auto Folder Playlist")
    t.equal("no file: sort order shown", shown.sort, "Date modified, oldest first")
    t.equal("no file: video types shown", shown.types, DEFAULT_LIST)
    t.equal("no file: no note", shown.note, "")
    has("the default list is named", widget_at(ext, "label", 2, 3).text, "default list:<br>" .. DEFAULT_LIST)
    click(ext, "Cancel")
    closed("Cancel", ext)
    t.equal("Cancel writes nothing", settings.read(), nil)

    -- A pick and two types, then Save.
    ext = activate()
    pick(sort_input(ext), "Name, A to Z")
    types_input(ext).text = "mp4, .MKV"
    click(ext, "Save")
    closed("Save", ext)
    t.equal("Save writes the file", settings.read(),
        settings.format({ sort = "name-az", extensions = { "mp4", "mkv" } }))

    -- Opened again: the file's values. Save without a pick keeps them, though
    -- get_value gives the first entry.
    ext = activate()
    shown = view(ext)
    t.equal("reopened: sort order shown", shown.sort, "Name, A to Z")
    t.equal("reopened: video types shown", shown.types, "mp4 mkv")
    pick(sort_input(ext), "Name, A to Z") -- the entry shown: no change
    t.equal("reopened: get_value gives the first entry (VLC's bug, copied)", (sort_input(ext):get_value()), 1)
    click(ext, "Save")
    closed("Save without a pick", ext)
    t.equal("Save without a pick keeps the sort order", settings.parse(settings.read() or "").sort, "name-az")

    -- A word that isn't a file type: nothing written, a red note. Then an
    -- empty field saves the default list.
    local before = settings.read()
    ext = activate()
    types_input(ext).text = "mp4 m<v avi"
    click(ext, "Save")
    still_open("a wrong type", ext)
    t.equal("a wrong type: nothing written", settings.read(), before)
    has("a wrong type: the note is red", note(ext), '<span style="color:#c00000">')
    has("a wrong type: the note names it, escaped", note(ext), '"m&lt;v"')
    types_input(ext).text = "  "
    click(ext, "Save")
    closed("an empty field", ext)
    t.equal("an empty field: the default list saved", settings.read(),
        settings.format({ sort = "name-az", extensions = settings.defaults().extensions }))

    -- A wrong value in the file: the default shown, and a note. X closes
    -- without writing.
    local by_hand = "sort=sideways\r\nextensions=mp4\r\n"
    write_file(settings.path(), by_hand)
    ext = activate()
    shown = view(ext)
    t.equal("a wrong value: the default sort order shown", shown.sort, "Date modified, oldest first")
    t.equal("a wrong value: video types shown", shown.types, "mp4")
    has("a wrong value: the note names it", shown.note, 'autofolder.ini line 1: unknown sort order "sideways"')
    has("a wrong value: the note says Save rewrites", shown.note, "<br>Save rewrites the file with the values shown.")
    call(ext, ext.env.close)
    closed("X", ext)
    t.equal("X writes nothing", settings.read(), by_hand)

    -- The file can't be read or written (its path is a folder): the defaults
    -- and a note; Save fails and the dialog stays open.
    local real_path = settings.path
    local folder = (config.media:gsub("[\\/]+$", ""))
    settings.path = function() return folder end
    ext = activate()
    shown = view(ext)
    t.equal("unreadable: the default sort order shown", shown.sort, "Date modified, oldest first")
    t.equal("unreadable: the default video types shown", shown.types, DEFAULT_LIST)
    has("unreadable: a note", shown.note, "Cannot read " .. folder .. ": showing the defaults.")
    click(ext, "Save")
    still_open("cannot write", ext)
    has("cannot write: a red note", note(ext), "Not saved: cannot write " .. folder .. ".")
    click(ext, "Cancel")
    closed("Cancel after a failed Save", ext)
    settings.path = real_path
end)
