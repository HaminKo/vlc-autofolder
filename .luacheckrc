-- luacheck settings. VLC 3.0's embedded Lua is 5.1.
std = "lua51"

-- Set by VLC for every script: the vlc.* API, and the script's own options
-- from the "lua-config" setting.
read_globals = { "vlc", "config" }

-- Extension scripts (To do 3) define these functions for VLC to call.
files["lua/extensions"] = {
    globals = {
        "descriptor", "activate", "deactivate", "close", "menu", "trigger_menu",
        "meta_changed", "input_changed", "playing_changed",
    },
}
