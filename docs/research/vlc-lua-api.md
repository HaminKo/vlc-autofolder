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
- **Chain options:** `config_ChainParse(p_intf, "lua-", ...)` reads options `intf` and `config` from the interface chain. So `extraintf=luaintf{intf=autofolder}` should select our script without changing the global `lua-intf` setting. **Measured 2026-11-10: works.** `--extraintf "luaintf{intf=a}:luaintf{intf=b}"` runs two Lua interface scripts side by side, each found in the user `lua\intf\` folder. The global `lua-config` string reaches chained scripts too: script `a` gets `config.a`.
- **lua-config:** the string is run as `config={...}`, and the subtable `config[<script name>]` becomes the script's global `config` (an empty table if missing). Example: `lua-config=autofolder={sort="name"}`.
- **No `vlc.misc.should_die` in 3.0.** `vlc.misc` has only `version`, `copyright`, `license`, `action_id`, `mdate`, `mwait` and `quit`. **Measured 2026-11-11:** `vlc.misc.should_die` is nil.
- **`vlc.misc.mwait(t)`** waits until the absolute time `t` (microseconds, compare `vlc.misc.mdate()`). The wait can be interrupted, and then it raises the Lua error `"Interrupted."`.
- **Exit:** `Close_LuaIntf` interrupts the script's waits (`vlclua_fd_interrupt`), then joins the thread. So the script ends when `mwait` raises "Interrupted.", and **the main loop must not catch that error** (no `pcall` around `mwait`). A script stuck in a pure Lua loop would probably block VLC from closing. **Measured 2026-11-10: clean.** After `vlc.misc.quit()`, a script waiting in an `mwait` loop ends at once; VLC exited ~0.05 s later with exit code 0. VLC logs this at error level on every close, e.g. `lua error: Error loading script C:\...\lua\intf\autofolder.lua: ...autofolder.lua:17: Interrupted.`, so Tools → Messages shows one such error per close: expected, not a bug.
- **Libraries** opened for interface scripts: the standard Lua libraries, plus `config`, `httpd`, `input`, `msg`, `misc`, `object`, `osd`, `playlist`, `sd_intf`, `stream`, `strings`, `variables`, `video`, `vlm`, `volume`, `gettext`, `xml`, `equalizer`, `io` (vlcio), `errno`, the fd/net functions, and `win` on Windows.
  - **Measured 2026-11-10:** `vlc.net` and `vlc.io` are tables in an interface script. ~~Unverified until To do 1 step B: that `stat` and `opendir` work there.~~ **Measured 2026-11-11: they work** (tests\lua\intf\test_api.lua; details under "Files and folders"). The README says the net namespace is usable "for interfaces and extensions".
- No change callbacks: `vlc.var.add_callback` is not in the 3.0 README (only `var.trigger_callback`). The script must **poll**, e.g. `vlc.playlist.current()` every 300–500 ms. **Measured 2026-11-11:** `vlc.var.add_callback` is nil.
- Modules: VLC's own `cli` interface loads `require "host"` from `lua\intf\modules\`. So a helper module in `lua\intf\modules\` should load with `require`. **Measured 2026-11-10: works**, from the user folder too. `package.path` lists, in order: the user `lua\modules\` and `lua\intf\modules\`, then the same two in VLC's own `lua\` folder (`?.luac`, `?.lua`, `?.vle` each).

## Files and folders (source: libs/net.c, README)
- **`vlc.net.stat(path)`** takes a local path, not a URI. It returns nil on failure; otherwise a table with:
  - `type`: `"file"`, `"dir"`, ...
  - `mode`, `uid`, `gid`, `size`
  - `access_time`, `modification_time`, `creation_time`: from st_atime, st_mtime, st_ctime, in seconds.
  - So `modification_time` exists in 3.0.
  - **Measured 2026-11-11** (Windows 11, NTFS, test_api.lua):
    - Works on Unicode names (é, Japanese, an emoji outside the BMP) and on UNC paths (`\\localhost\C$\...`, same times as the local path). Only the local admin share was tried; a real network share is a manual check (To do 5).
    - `modification_time` is the true Unix time: it matched the dates the test runner set, for a January file and for a July file (summer time, Eastern time zone). So no DST shift from the old MSVCRT `stat`.
    - `type` is `"file"` or `"dir"`; `size` is in bytes; `uid` and `gid` are 0.
    - `mode` is 33206 (octal 100666) for a file and 16895 (octal 40777) for a folder. A file with Windows' **hidden attribute has the same mode**: Lua can't see that attribute.
    - A missing path returns nil. A folder path with a trailing backslash works.
- **`vlc.net.opendir(path)`** returns an array of names. It raises an error if the folder can't be opened. It does no filtering of its own: ~~unverified whether Windows `vlc_readdir` includes `.` and `..`~~.
  - **Measured 2026-11-11:**
    - It **includes `.` and `..`** (the first entry was `.`), plus subfolders, dot-names and attribute-hidden files. Filter them yourself.
    - Unicode names come back as UTF-8 that `stat` accepts.
    - `/` separators work as well as `\`.
    - A missing folder raises ``cannot open directory `<path>'.``
    - The entry order wasn't checked: sort the list yourself.
  - `vlc.io.readdir(path)` exists too and also returns `.` (same count as `opendir`).
- On Windows, `vlc.net` does not register `read` and `write` (`#ifndef _WIN32`); `stat` and `opendir` are registered.
- **`vlc.io.open(path, mode)`** and **`vlc.io.readdir(path)`** take UTF-8 paths.
  - Use `vlc.io.open` for the settings file. Plain Lua `io.open` uses the ANSI code page on Windows and fails on non-ASCII paths. **Measured 2026-11-11:** plain `io.open` fails on `café.mkv`; `vlc.io.open` opens it.
  - `file:read("*a")` works on a `vlc.io` file (the test library reads `videos.txt` this way).
- **`vlc.config.userdatadir()`** returns the user's VLC data folder (on Windows `%APPDATA%\vlc`). It's a good place for a settings file.
  - **Measured 2026-11-10:** in portable mode it returns the `portable` folder next to vlc.exe; `vlc.config.datadir()` returns VLC's program folder.
- **Measured 2026-11-10:** `vlc.io.open(path, "w")` with `:write`, `:flush` and `:close` works in an interface script (the test library writes its results this way).
  - When it can't open the file (a folder that doesn't exist), it returns **no value at all**, not `nil` plus a message like Lua's `io.open`. So `assert(vlc.io.open(...))` only says "bad argument #1 to 'assert' (value expected)"; check the result and raise your own message.

## Strings and URIs (source: README)
- `vlc.strings.make_uri(path, [scheme])` converts a path to a URI.
- `vlc.strings.decode_uri(...)` and `vlc.strings.encode_uri_component(...)` decode and encode URIs.
- **No `vlc.strings.make_path` in the 3.0 README.** To get a local path from `file:///C:/...` the script must decode the URI and convert it itself.
  - **Wrong, measured 2026-11-11:** `vlc.strings.make_path` exists in 3.0.24, although the README leaves it out. It gives back every local path exactly (all 17 test names), but **drops the server of a UNC path**: `file://localhost/C%24/Users/...` becomes `C$\Users\...`. So for UNC the script still converts itself.
  - UNC paths arrive as `file://server/share/...`.
  - ~~Unverified: what `make_uri` produces for a UNC path and for names with `#`, `%`, `[`, `]` or Unicode.~~ **Measured 2026-11-11** (test_api.lua):
    - `make_uri` gives **exactly the URIs VLC makes itself**, for all 17 test names: from the command line (that is, Explorer) and from opening a folder. So URIs can be compared as strings, as long as both come from VLC.
    - Encoding: forward slashes, `file:///C:/...` for a drive and `file://server/share/...` for UNC.
      - Kept as is: letters, digits, `.`, `-`.
      - Percent-encoded: space `%20`, `#` `%23`, `%` `%25`, `&` `%26`, `'` `%27`, `,` `%2C`, `+` `%2B`, `=` `%3D`, `;` `%3B`, `[` `]` `%5B` `%5D`, `$` `%24`.
      - Non-ASCII: the UTF-8 bytes (`é` → `%C3%A9`).
    - Back to a path: `decode_uri`, then strip `file:///` and turn `/` into `\`; for UNC strip `file://` and prefix `\\`. That gave back every path exactly, including a literal `%20` in a name (`%2520`).
    - `url_parse` on a UNC URI gives `protocol=file`, `host=localhost`, `path=/C%24/...` (still encoded), `port=0`.
  - URIs from other sources (Qt drag and drop, the Open dialog) are not compared yet: manual check in To do 5.

## Playlist (source: libs/playlist.c, README)
- Registered: `prev`, `next`, `skip`, `play`, `pause`, `stop`, `clear`, `repeat`/`repeat_`, `loop`, `random`, `goto` (Lua < 5.2 only, so present here), `gotoitem`, `add`, `enqueue`, `get`, `search`, `current`, `sort`, `status`, `delete`, `move`.
- **`current()`** returns the playing item's id, or -1.
- **`add(items)` / `enqueue(items)`**
  - Each item is a table with `path` (a URI), `name`, `options`, and more.
  - They append with `playlist_AddInput`; `add` also plays, `enqueue` doesn't.
  - They return **a count, not item ids**. Find the new ids afterwards with `get("playlist")`. **Measured 2026-11-11:** `enqueue` of 3 items returned 3; the playlist node had id 1, and items got ids 2, 3, ... in the order they were added.
- **`get(what)`**
  - `"playlist"` or `"normal"` returns the playing node; `"ml"` the media library; `"root"` the root; a number returns one item by id.
  - Each item is a table: `id`, `flags` (`disabled`, `ro`), `name`, `path` (URI), `duration` (seconds, -1 if unknown), `nb_played`, and `children` for nodes.
- **`delete(id)`** returns 0, or -1 if there is no such id.
- **`move(id_item, id_where)`**
  - If `id_where` is a node, the item becomes its **first** child.
  - ~~Otherwise the item is placed **after** `id_where`, in the same parent.~~ **Wrong, measured 2026-11-11.** The 3.0.x source (`vlclua_playlist_move`) computes the new index from **item ids**: `id_where - first_child_id + 1`, not from `id_where`'s position. That is only right when ids happen to follow the playlist order.
    - An index in range puts the item in the wrong place. Example: "move Episode 2 after Episode 1" left Episode 2 in front of Episode 1.
    - An index out of range **crashes VLC**: index -1 gave an access violation (exit code 0xC0000005).
  - It returns 0 on success and -1 if either id is missing (measured).
  - ~~So "before the playing item" means "after the item before it"~~. **Replaced:** move only into the playlist node (`move(id, get("playlist").id)`, the item becomes first). To place files around the playing one:
    - Enqueue the files that come after it, in order: they are appended.
    - Enqueue the files that come before it, then move each to the front, last one first.
  - ~~Unverified: that moving items around the playing item keeps it playing and keeps Next/Previous correct.~~ **Measured 2026-11-11** (test_move.lua), with moves into the node:
    - The playing item keeps playing: same id, and the time doesn't go back.
    - Next and Previous follow the new order.
    - Moving the playing item itself to the front also keeps it playing, and Next then follows the new order.
- `auto-preparse=1` (default) makes VLC read metadata of every added item. With hundreds of files, especially on a network share, that is background work to watch in To do 2.
- **Opening a folder** (an item whose URI is a folder; measured 2026-11-11):
  - When played, VLC's `directory` module replaces the folder item **in place with a flat list** of its entries (the default `playlist-tree` is off). A subfolder becomes one item, expanded the same way when it plays.
  - The subfolder came first, before names that sort ahead of it. The non-video files of the test folder (`.srt`, `.jpg`, `.txt`, `.nfo`, `.m3u`) and the dot-name `.dot-hidden.mkv` are left out; the attribute-hidden file is kept.
  - The order is roughly natural and case-insensitive, but not quite: `Episode 1, Episode 2, Episode 10, episode 3`.
  - The entries' URIs equal `make_uri` of their paths.

## One-instance mode (measured 2026-11-11, tests\spike-one-instance.ps1)
First from memory of `src/win32/specific.c` (both now confirmed):
- When a second VLC is started with one-instance active, it sends its files to the running VLC, which **appends** them to the playlist and plays the first one, unless `playlist-enqueue=1`. It **doesn't clear** the old playlist.
- `one-instance-when-started-from-file=1` (default) makes double-clicks in Explorer use one instance even with `one-instance=0`.

Source (3.0.x `src/win32/specific.c`, `modules/control/win_msg.c`):
- A VLC that is in one-instance mode takes a named mutex `VLC ipc 3.0.24`. If no other VLC holds it, this VLC becomes the receiver: it loads the `win_msg` interface, which waits for files from later VLCs. Otherwise it sends its file arguments to the receiver (`WM_COPYDATA`) and exits with code 0.
- The name holds only the version, so **any two VLC 3.0.24 copies hand files to each other**: the portable test VLC and the installed one included. That's why test runs pass `--no-one-instance --no-one-instance-when-started-from-file`.
- The receiver calls `playlist_AddExt` for each file, with "play now" for the first file unless the *sending* VLC has `playlist-enqueue` on.

What Explorer runs (VLC's registered `.mkv` type, `HKCR\VLC.mkv\shell`):
- Open (double-click): `vlc.exe --started-from-file "%1"`
- "Add to VLC media player's Playlist": `vlc.exe --started-from-file --playlist-enqueue "%1"`
- "Play with VLC media player": `vlc.exe --started-from-file --no-playlist-enqueue "%1"`
- A double-click only runs these when VLC is the default app for the file type. On the dev PC, video files open in Windows Media Player, so the double-click flow needs VLC chosen as the default app first (README troubleshooting, To do 5).

Measured with the portable test VLC, default settings, one case each (the spike prints this table's data):

| Case | Second VLC | First VLC's playlist afterwards |
|---|---|---|
| Double-click, then another double-click (`--started-from-file` both) | hands over, exits after 0.1 s | new file **appended and playing**; old one still in the list |
| Double-click, then "Add to playlist" (`--playlist-enqueue` on the second) | hands over | new file appended; the old one **keeps playing** |
| VLC started without `--started-from-file` (Start menu), then a double-click | **runs as a separate VLC** | unchanged |
| `--one-instance` on both | hands over | appended and playing |
| `--no-one-instance-when-started-from-file` on both | separate VLC | unchanged |

- For the folder logic: after a double-click into a running VLC, the opened file is the **last** item and becomes the playing one. With "Add to playlist" the playing item doesn't change, so a script that reacts to a new playing item does nothing.
- A VLC opened from the Start menu doesn't receive later double-clicks: each starts its own VLC. Worth a README line.
- **Measured: the switch took ~6 s** when the old file was Episode 1.mkv, and 0.2–0.3 s with Episode 10.mkv. VLC auto-loads `Episode 1.srt` with Episode 1.mkv, and with no video output (headless test) stopping that file waited for the subtitle (log: "no vout found, dropping subpicture", then `killing decoder fourcc 'subt'`). Test VLCs now pass `--no-sub-autodetect-file`. Not seen in the windowed VLC (not tested).

## Test isolation (measured 2026-11-10, To do 1 step A)
From memory of `src/win32/dirs.c`:
- VLC 3.0 finds its user folder with `SHGetFolderPathW(CSIDL_APPDATA)`, **not** the `APPDATA` environment variable. So setting `$env:APPDATA` probably does **not** isolate a test run. **Not tested:** the portable folder made it unnecessary.
- VLC uses a `portable` folder next to vlc.exe instead, if one exists. **Measured: true.** With `tools\vlc\portable\`, the test VLC finds Lua scripts in `portable\lua\intf\`, `userdatadir()` returns `portable\`, and the real `%APPDATA%\vlc` stays unchanged (file list, sizes and dates compared before and after every test run).
- The setup (decision in decisions.md): the portable VLC 3.0.24 zip in `tools\vlc`, made by `tests\setup-tools.ps1`.

Other facts found while setting it up (measured 2026-11-10):
- `https://get.videolan.org/...zip` answers PowerShell's browser-like user agent with an HTML mirror page (29 KB) instead of the zip. `https://download.videolan.org/pub/videolan/vlc/3.0.24/win64/vlc-3.0.24-win64.zip` serves the zip directly (82.8 MB, SHA-256 `fcf30850…6323`, matching VideoLAN's `.sha256` file).
- The zip has no plugin cache (`plugins\plugins.dat`); `vlc-cache-gen.exe plugins` makes it, as the installer does. The first VLC start after unpacking took ~10 s, later starts ~0.3 s until the Lua script runs (cause of the first slow start not checked; probably Windows scanning the new DLLs).
- Without `--no-media-library`, VLC writes `ml.xspf` into its user folder on exit, even with `-I dummy`.
- `-I dummy --dummy-quiet --vout dummy --aout dummy` shows no window or console; a file on the command line plays normally.
- A raw YUV4MPEG2 file plays when named `.mkv` or `.mp4`: the `rawvid` demuxer rejects it ("invalid or no framerate specified"), then the `avcodec` demuxer takes it. VLC reports `length` 120000000 and the item `duration` 120 for a 2-minute file.
- `vlc.var.get(input, "time")` is in microseconds (1.9 million after ~2 s of playback).
- A file given on the command line gets the item `path` `file:///C:/Users/.../media/Episode%202.mkv`: forward slashes, three slashes after `file:`, a space as `%20` (the full comparison with `make_uri` is under "Strings and URIs").

Found in To do 1 step B (measured 2026-11-11):
- **Crash dumps ignore the portable folder.** When the test VLC crashed, `vlc.exe` wrote `crashdump\<id>.dmp` into the real `%APPDATA%\vlc` (path from `SHGetFolderPathW`). A VLC with crash handling on checks that folder at its next start and asks to send the report. `vlc.exe` itself reads `--no-crashdump` (the string is in vlc.exe; the option isn't passed on to libvlc), and with it a crashing test VLC left `%APPDATA%\vlc` unchanged (measured). All test VLCs pass it now. The one dump written before the fix was moved out of `%APPDATA%\vlc` by hand.
- The first two test runs of a day were slow: opening the test video took 7.9 s and 3.5 s, later runs ~1.2 s per case (cause not checked; probably Windows scanning the plugin DLLs again). The smoke test now waits up to 5 s for playback instead of a fixed 1 s.
- Timing of the 3 cases (smoke, api, move): ~8 s per run (three runs in a row).

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
- src/win32/specific.c (one-instance sender): https://raw.githubusercontent.com/videolan/vlc/3.0.x/src/win32/specific.c
- modules/control/win_msg.c (one-instance receiver): https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/control/win_msg.c
- "Add similar files from folder" add-on: https://store.kde.org/p/1153993
- vlc_autoPlaylist: https://github.com/PhoenixWhitebrow/vlc_autoPlaylist
