# VLC 3.0 Lua API: what the script can use

What VLC 3.0.x (target: 3.0.24 on Windows) really offers a Lua interface script, and how this PC's VLC is set up.
Each fact is marked:
- **Measured**: checked on the dev PC.
- **Source**: read in the VLC 3.0.x source; not yet run.
- **Unverified**: from memory or inference; must be checked before relying on it.

When a fact turns out wrong, mark it wrong here and say what replaced it; don't delete it.

## This PC's VLC (measured 2026-11-10)
- vlc.exe version 3.0.24, standard install in Program Files (path in docs/local.md). Not on PATH.
- VLC's bundled Lua scripts are Lua **5.1** bytecode: the header of `lua\intf\dummy.luac` is `1B 4C 75 61 51`. So our code must be Lua 5.1: no `goto`, no `//`, no `utf8` library, and `#` on strings counts bytes.
- The user's `vlcrc` (in `%APPDATA%\vlc`):
  - It is UTF-8 **with BOM** (`EF BB BF`), and lines end with **LF only** (5316 LF, 0 CRLF). An install script must keep both. PowerShell 5.1 `Set-Content` writes ANSI, so use .NET file APIs.
  - Its header says `vlc 3.0.23`: VLC only rewrites the file when settings are saved.
  - Settings live in sections: `[lua]` at line ~1539, `[qt]` at ~1615, `[core]` at ~4043. `extraintf` is in `[core]`, `lua-intf` and `lua-config` in `[lua]`.
  - Relevant settings are all at their defaults (commented out): `extraintf=`, `lua-intf=dummy`, `lua-config=`, `one-instance=0`, `one-instance-when-started-from-file=1`, `playlist-enqueue=0`, `auto-preparse=1`, `playlist-autostart=1`.
- There is no `%APPDATA%\vlc\lua\` folder yet.

## Interface script lifecycle (source: modules/lua/intf.c, libs/misc.c)
- The script is found by name with `vlclua_find_file("intf", name)`; the name comes from the `lua-intf` option. It is unknown whether a full path is accepted.
- **Chain options:** `config_ChainParse(p_intf, "lua-", ...)` reads options `intf` and `config` from the interface chain. So `extraintf=luaintf{intf=autofolder}` should select our script without changing the global `lua-intf` setting. **Unverified:** try it in To do 1.
- **lua-config:** the string is run as `config={...}`, and the subtable `config[<script name>]` becomes the script's global `config` (an empty table if missing). Example: `lua-config=autofolder={sort="name"}`.
- **No `vlc.misc.should_die` in 3.0.** `vlc.misc` has only `version`, `copyright`, `license`, `action_id`, `mdate`, `mwait` and `quit`.
- **`vlc.misc.mwait(t)`** waits until the absolute time `t` (microseconds, compare `vlc.misc.mdate()`). The wait can be interrupted, and then it raises the Lua error `"Interrupted."`.
- **Exit:** `Close_LuaIntf` interrupts the script's waits (`vlclua_fd_interrupt`), then joins the thread. So the script ends when `mwait` raises "Interrupted.", and **the main loop must not catch that error** (no `pcall` around `mwait`). A script stuck in a pure Lua loop would probably block VLC from closing. **Unverified:** clean shutdown in To do 1.
- **Libraries** opened for interface scripts: the standard Lua libraries, plus `config`, `httpd`, `input`, `msg`, `misc`, `object`, `osd`, `playlist`, `sd_intf`, `stream`, `strings`, `variables`, `video`, `vlm`, `volume`, `gettext`, `xml`, `equalizer`, `io` (vlcio), `errno`, the fd/net functions, and `win` on Windows.
  - **Unverified:** that `vlc.net` (with `stat` and `opendir`) is really present in an interface script. The README says the net namespace is usable "for interfaces and extensions".
- No change callbacks: `vlc.var.add_callback` is not in the 3.0 README (only `var.trigger_callback`). The script must **poll**, e.g. `vlc.playlist.current()` every 300–500 ms.
- Modules: VLC's own `cli` interface loads `require "host"` from `lua\intf\modules\`. So a helper module in `lua\intf\modules\` should load with `require`. **Unverified.**

## Files and folders (source: libs/net.c, README)
- **`vlc.net.stat(path)`** takes a local path, not a URI. It returns nil on failure; otherwise a table with:
  - `type`: `"file"`, `"dir"`, ...
  - `mode`, `uid`, `gid`, `size`
  - `access_time`, `modification_time`, `creation_time`: from st_atime, st_mtime, st_ctime, in seconds.
  - So `modification_time` exists in 3.0.
- **`vlc.net.opendir(path)`** returns an array of names. It raises an error if the folder can't be opened. It does no filtering of its own: **unverified** whether Windows `vlc_readdir` includes `.` and `..`.
- On Windows, `vlc.net` does not register `read` and `write` (`#ifndef _WIN32`); `stat` and `opendir` are registered.
- **`vlc.io.open(path, mode)`** and **`vlc.io.readdir(path)`** take UTF-8 paths.
  - Use `vlc.io.open` for the settings file. Plain Lua `io.open` uses the ANSI code page on Windows and fails on non-ASCII paths (**unverified** for VLC's Lua build, but the usual Windows behaviour).
- **`vlc.config.userdatadir()`** returns the user's VLC data folder (on Windows `%APPDATA%\vlc`). It's a good place for a settings file.

## Strings and URIs (source: README)
- `vlc.strings.make_uri(path, [scheme])` converts a path to a URI.
- `vlc.strings.decode_uri(...)` and `vlc.strings.encode_uri_component(...)` decode and encode URIs.
- **No `vlc.strings.make_path` in the 3.0 README.** To get a local path from `file:///C:/...` the script must decode the URI and convert it itself.
  - UNC paths arrive as `file://server/share/...`.
  - **Unverified:** what `make_uri` produces for a UNC path and for names with `#`, `%`, `[`, `]` or Unicode. Compare it with the URIs VLC creates itself (they must match exactly for duplicate checks).

## Playlist (source: libs/playlist.c, README)
- Registered: `prev`, `next`, `skip`, `play`, `pause`, `stop`, `clear`, `repeat`/`repeat_`, `loop`, `random`, `goto` (Lua < 5.2 only, so present here), `gotoitem`, `add`, `enqueue`, `get`, `search`, `current`, `sort`, `status`, `delete`, `move`.
- **`current()`** returns the playing item's id, or -1.
- **`add(items)` / `enqueue(items)`**
  - Each item is a table with `path` (a URI), `name`, `options`, and more.
  - They append with `playlist_AddInput`; `add` also plays, `enqueue` doesn't.
  - They return **a count, not item ids**. Find the new ids afterwards with `get("playlist")`.
- **`get(what)`**
  - `"playlist"` or `"normal"` returns the playing node; `"ml"` the media library; `"root"` the root; a number returns one item by id.
  - Each item is a table: `id`, `flags` (`disabled`, `ro`), `name`, `path` (URI), `duration` (seconds, -1 if unknown), `nb_played`, and `children` for nodes.
- **`delete(id)`** returns 0, or -1 if there is no such id.
- **`move(id_item, id_where)`**
  - If `id_where` is a node, the item becomes its **first** child.
  - Otherwise the item is placed **after** `id_where`, in the same parent.
  - It returns -1 if either id is missing.
  - So "before the playing item" means "after the item before it", or "first in the playlist node" when the playing item is first.
  - **Unverified:** that moving items around the playing item keeps it playing and keeps Next/Previous correct. The move sets a "reset currently playing" flag inside VLC.
- `auto-preparse=1` (default) makes VLC read metadata of every added item. With hundreds of files, especially on a network share, that is background work to watch in To do 2.

## One-instance mode (unverified)
From memory of `src/win32/specific.c`, not yet read or tested:
- When a second VLC is started with one-instance active, it sends its files to the running VLC, which **appends** them to the playlist and plays the first one, unless `playlist-enqueue=1`. It **doesn't clear** the old playlist.
- `one-instance-when-started-from-file=1` (default) makes double-clicks in Explorer use one instance even with `one-instance=0`.

Check both in To do 1 or 2 and document them in the README.

## Test isolation (unverified)
From memory of `src/win32/dirs.c`:
- VLC 3.0 finds its user folder with `SHGetFolderPathW(CSIDL_APPDATA)`, **not** the `APPDATA` environment variable. So setting `$env:APPDATA` probably does **not** isolate a test run.
- VLC uses a `portable` folder next to vlc.exe instead, if one exists.
- Plan for To do 1: a portable copy of VLC 3.0.24 (zip from videolan.org) in `tools\`, with a `portable` folder, so tests never touch the real settings.

## Prior art (searched 2026-11-10)
- No ready-made auto-starting interface script for VLC 3 was found.
- Existing VLC add-ons are extensions that need a menu click each session, such as "Add similar files from folder" on store.kde.org, or wrapper scripts such as vlc_autoPlaylist (Bash/AppleScript).
- Other players have this built in: MPC-HC, MPC-BE, PotPlayer, and mpv (`autoload.lua`).

## Sources
- VLC 3.0 Lua README: https://raw.githubusercontent.com/videolan/vlc/3.0.x/share/lua/README.txt
- modules/lua/libs/net.c: https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/lua/libs/net.c
- modules/lua/libs/playlist.c: https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/lua/libs/playlist.c
- modules/lua/libs/misc.c: https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/lua/libs/misc.c
- modules/lua/intf.c: https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/lua/intf.c
- "Add similar files from folder" add-on: https://store.kde.org/p/1153993
- vlc_autoPlaylist: https://github.com/PhoenixWhitebrow/vlc_autoPlaylist
