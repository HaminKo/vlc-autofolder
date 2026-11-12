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
- **An early `vlc.misc.quit()` is lost (measured 2026-11-11, To do 2 step A).** Extra interfaces start inside `libvlc_new`, before vlc.exe sets its exit handler (in 3.0 source, `libvlc_wait` sets it). A quit before that only logs `main debug: no exit handler`, and VLC keeps running. A test driver that quit 0.1 s after start left VLC running in 5 of 6 runs; quitting again every 0.5 s until VLC closes fixed it (6 of 6; the log showed two lost quits). The test library does this now. autofolder never quits VLC, so it isn't affected.
- **Libraries** opened for interface scripts: the standard Lua libraries, plus `config`, `httpd`, `input`, `msg`, `misc`, `object`, `osd`, `playlist`, `sd_intf`, `stream`, `strings`, `variables`, `video`, `vlm`, `volume`, `gettext`, `xml`, `equalizer`, `io` (vlcio), `errno`, the fd/net functions, and `win` on Windows.
  - **Measured 2026-11-10:** `vlc.net` and `vlc.io` are tables in an interface script. ~~Unverified until To do 1 step B: that `stat` and `opendir` work there.~~ **Measured 2026-11-11: they work** (tests\lua\intf\test_api.lua; details under "Files and folders"). The README says the net namespace is usable "for interfaces and extensions".
- No change callbacks: `vlc.var.add_callback` is not in the 3.0 README (only `var.trigger_callback`). The script must **poll**, e.g. `vlc.playlist.current()` every 300–500 ms. **Measured 2026-11-11:** `vlc.var.add_callback` is nil.
- Modules: VLC's own `cli` interface loads `require "host"` from `lua\intf\modules\`. So a helper module in `lua\intf\modules\` should load with `require`. **Measured 2026-11-10: works**, from the user folder too. `package.path` lists, in order: the user `lua\modules\` and `lua\intf\modules\`, then the same two in VLC's own `lua\` folder (`?.luac`, `?.lua`, `?.vle` each).
  - **Measured 2026-11-11 (To do 3 step A):** a module in the user `lua\modules\` (`autofolder_settings`) loads with `require` from an interface script, and from a module in `lua\intf\modules\` that the script loaded.
  - For an extension script (`lua\extensions\`), the 3.0 source (`vlclua_add_modules_path` in modules/lua/vlc.c) adds the script folder's parent `lua\modules\` and `lua\extensions\modules\` the same way, so a shared module goes in `lua\modules\`. ~~**Source only:** to be measured in To do 3 step B.~~ **Measured 2026-11-11 (To do 3 step B manual test):** the dialog in the user `lua\extensions\` loads `autofolder_settings` from the user `lua\modules\` with `require`.

## Files and folders (source: libs/net.c, README)
- **`vlc.net.stat(path)`** takes a local path, not a URI. It returns nil on failure; otherwise a table with:
  - `type`: `"file"`, `"dir"`, ...
  - `mode`, `uid`, `gid`, `size`
  - `access_time`, `modification_time`, `creation_time`: from st_atime, st_mtime, st_ctime, in seconds.
  - So `modification_time` exists in 3.0.
  - **Measured 2026-11-11** (Windows 11, NTFS, test_api.lua):
    - Works on Unicode names (é, Japanese, an emoji outside the BMP) and on UNC paths (`\\localhost\C$\...`, same times as the local path). Only the local admin share was tried; a real network share is a manual check (To do 5).
    - **Through a share it's much slower (measured 2026-11-11, To do 2 step D):** listing and `stat`-ing 500 files took 22–32 ms on the local disk and 757–875 ms through `\\localhost\C$` and `\\127.0.0.1\C$` (one run each), so ~1.5 ms per file even with no network in between. A real network share will be slower (not measured).
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
  - **Measured 2026-11-11:** the path has no trailing backslash (`...\tools\vlc\portable`). The settings file `autofolder.ini` goes there (decisions.md, "Sort-order switch").
- **Measured 2026-11-10:** `vlc.io.open(path, "w")` with `:write`, `:flush` and `:close` works in an interface script (the test library writes its results this way).
  - When it can't open the file (a folder that doesn't exist), it returns **no value at all**, not `nil` plus a message like Lua's `io.open`. So `assert(vlc.io.open(...))` only says "bad argument #1 to 'assert' (value expected)"; check the result and raise your own message.
  - **Measured 2026-11-11 (To do 2 step C, test_rules.lua):** modes `"rb"` and `"wb"` with `read("*a")` copy a 185 KB video (the copy was scanned and enqueued as a video; its bytes weren't compared). **`vlc.io.unlink(path)`** exists and deletes a file.
  - **Measured 2026-11-11 (To do 3 step A, test_settings.lua):** `vlc.io.open(folder, "rb")` on a folder that exists also returns no value. So "no value" alone doesn't tell a missing file from one that can't be read; `autofolder_settings.read` asks `vlc.net.stat` then.
  - **Source (3.0.24 libs/io.c, read 2026-11-11, To do 3 step B):** `file:write(...)` returns a boolean (false when `fwrite` wrote nothing); `file:flush()` and `file:close()` return nothing, so an error at close (e.g. a full disk) can't be seen.
  - A settings file rewritten while VLC runs was picked up within the 5 s the test allows each time (read every ~1 s, compared by text). How long one read takes wasn't measured; it is a ~200-byte file.

## Strings and URIs (source: README)
- `vlc.strings.make_uri(path, [scheme])` converts a path to a URI.
- `vlc.strings.decode_uri(...)` and `vlc.strings.encode_uri_component(...)` decode and encode URIs.
- **No `vlc.strings.make_path` in the 3.0 README.** To get a local path from `file:///C:/...` the script must decode the URI and convert it itself.
  - **Wrong, measured 2026-11-11:** `vlc.strings.make_path` exists in 3.0.24, although the README leaves it out. It gives back every local path exactly (all 17 test names), but ~~**drops the server of a UNC path**~~: `file://localhost/C%24/Users/...` becomes `C$\Users\...`. So for UNC the script still converts itself.
    - **Corrected, measured 2026-11-11 (To do 2 step D):** it drops only the server **`localhost`**, which VLC takes as "this PC". `file://127.0.0.1/C%24/...` and `file://<computer name>/C%24/...` come back as `\\127.0.0.1\C$\...` and `\\<computer name>\C$\...`. autofolder keeps its own conversion (`core.uri_to_path`, tested); it keeps every server.
    - **VLC itself can't open a `\\localhost\...` file** (measured, same step): VLC turns `file://localhost/C%24/...` into the path `C$\Users\...` and fails (`filesystem error: cannot open file C$\Users\...`, then "Your input can't be opened"). A real server name plays. That's why the tests use `\\127.0.0.1\C$\...` for UNC since step D; with `\\localhost` the step D spike's UNC build test failed on Previous and clicks, because no item could play.
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
  - **Measured 2026-11-11 (To do 2 step A):** it returns the new item's id **before VLC creates that item's input**: autofolder's build log line came before `Creating an input for 'Episode 2.mkv'`. So the folder is built while the opened file is still opening.
    - **Not always (measured 2026-11-11, To do 2 step B):** in all 5 build cases of one run, `Creating an input for '<opened file>'` came ~150 log lines before the build line. autofolder's first poll ran before playback started (it saw nothing playing), so the build came at the next poll. Which comes first depends on timing; the build must work both ways.
- **`gotoitem(id)`** plays the item with that id (measured 2026-11-11, test_build.lua).
- `nb_played` is 1 for an item that has started once (measured 2026-11-11, test_build.lua).
- **`add(items)` / `enqueue(items)`**
  - Each item is a table with `path` (a URI), `name`, `options`, and more.
  - They append with `playlist_AddInput`; `add` also plays, `enqueue` doesn't.
  - They return **a count, not item ids**. Find the new ids afterwards with `get("playlist")`. **Measured 2026-11-11:** `enqueue` of 3 items returned 3; the playlist node had id 1, and items got ids 2, 3, ... in the order they were added.
- **Files on VLC's command line get their ids in reverse order** (measured 2026-11-11, To do 2 step C, rules-several): `vlc.exe "Episode 1.mkv" "Episode 2.mkv"` gave the list `Episode 1.mkv` (id 3), `Episode 2.mkv` (id 2), and `Episode 1.mkv` played. So the playing first file has the highest id: "the newest item" must mean the **last by position**, not the highest id. (Probably because 3.0's `GetFilenames` walks the arguments from the last one, inserting each at the top: from memory of the source, not checked.)
- **`get(what)`**
  - `"playlist"` or `"normal"` returns the playing node; `"ml"` the media library; `"root"` the root; a number returns one item by id.
  - Each item is a table: `id`, `flags` (`disabled`, `ro`), `name`, `path` (URI), `duration` (seconds, -1 if unknown), `nb_played`, and `children` for nodes.
- **`delete(id)`** returns 0, or -1 if there is no such id.
  - **Measured 2026-11-11 (To do 2 step C, rules-switch and rules-refresh):** deleting items that don't play, right after another item started (15 at a folder switch; an earlier copy and an item whose file is gone at a refresh), keeps the playing item playing: same id, started once.
  - Ids come from a counter that only grows (3.0 source `i_last_playlist_id`, from memory, not checked; it fits every id measured so far), so an old id never names a new item; deleting it again returns -1.
- **`clear()`** empties the playlist node and stops playback; `current()` is then -1 (measured 2026-11-11, rules-refresh). A file opened after that gets a new id as usual.
- **`stop()`** keeps `current()` at the stopped item's id: still the same 5 s later (measured 2026-11-11, To do 3 step A, a draft of settings-live). So -1 doesn't mean "stopped".
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
    - **Also during a build (measured 2026-11-11, To do 2 step B, test_build.lua):** 0 to 15 moves in the same poll as the enqueue, right as the opened file starts. In all 5 cases the opened file kept its id, was started once (`nb_played` 1), and Previous played the file before it. ~~Not measured: whether the Qt playlist view shows the new order at once (manual test)~~ (see the next point), and ~~the time for hundreds of moves (step D)~~ (measured: 499 moves take 1–2 ms, see "Large folders" below).
    - **The Qt playlist window doesn't show a move of an item it already shows (measured 2026-11-11, To do 3 step A manual test).**
      - In the windowed test VLC, after `sort=name-az` was saved, the log said `re-sorted by name-az; 12 moves`. Playback then went on in name order: it's here.mp4, percent…, plus…, 日本語.mkv, 🎬 clip.mp4, then "nothing to play". The window kept the date order, also after Next.
      - The headless tests check the playlist itself, so they can't see this.
      - Source (3.0.x, `modules/gui/qt/components/playlist/playlist_model.cpp`): the window's model only reacts to:
        - an item added (`processItemAppend`)
        - an item removed (`processItemRemoval`)
        - its own drag and drop (`dropMove`)

        Nothing handles an item moved by the core.
    - From the same source, **not measured**:
      - VLC hands the "item added" event to the window's thread with `QApplication::postEvent` (input_manager.cpp), and the window places the item at its index in the playlist **when it handles the event**. So an item that is added and then moved shows in the right place only if the window handles the event after the move.
      - In the To do 2 build, 4 items were added and then moved before the opened file. The window showed them in the right place (one manual test).
      - The window re-reads the whole playlist (`rebuild`) when its search text changes (`filter`) and when its root item is removed.
    - **So a re-sort deletes and re-adds the items** (decisions.md, 2026-11-11). The settings-live case checks that the re-sorted items have new ids. **Measured by hand (2026-11-11, To do 3 step A tests 3–6):** 15 items re-added and placed, 5 sort changes in a row. The window showed the new order every time, with no item in a wrong row, so the race above didn't show.
    - **Also in a build (measured 2026-11-11, step A test 8):** Ctrl+O on Episode 2.mkv again, with its folder built (16 videos, date order). The new copy played, and the build moved it into the old copy's place (2nd). The window showed it **at the bottom**. That is To do 6.
    - **Read in the source (To do 6, 2026-11-11; vlc-3.0 `playlist_model.cpp`, not measured):**
      - `processItemAppend` reads the item's index in its parent (`pp_children`) **at the time it handles the event**, under the playlist lock, and inserts it at that row of its own list (`insertChild(newItem, pos)`).
      - `processItemRemoval` finds the item by id and removes it.
      - The only move the window makes is its own drag and drop (`dropMove`). `rebuild` runs only when the root item is removed or the search filter changes.
      - So the window is right after a script's changes when (1) the items that keep their id keep their order relative to each other (moving one is harmless if that order holds), and (2) the new items are added in their final order, after the deletions, and the window handles their events after the moves. Each insert then lands on its final row.
    - **So build and re-sort re-add only the folder items that must change order** (decisions.md, To do 6). `autofolder_core.keep_in_order` keeps the longest run in order around the fixed items (the playing one, the user's own). The rules-reopen, rules-refresh and settings-live cases check rule (1) (`testlib.kept_order`).
      - **Measured by hand (2026-11-11, To do 6 manual test, windowed test VLC, media folder):** Episode 2.mkv opened again (14 re-added, 0 moves), hash # sign.mkv opened again (11 re-added), a user's item added after the folder and Episode 2.mkv opened again (15 re-added, 2 moves: the folder went after the user's item), then a re-sort to name-az and Next. The window showed the playlist's order every time, so the event race above didn't show.
- `auto-preparse=1` (default) makes VLC read metadata of every added item. With hundreds of files, especially on a network share, that is background work to watch in To do 2.
  - **Measured 2026-11-11 (To do 2 step A):** after `enqueue`, the log shows `Creating an input for preparsing '<name>'` for each added item, one after another, interleaved with the opening of the playing file.
  - On the first test run of the day, the smoke case's Episode 2.mkv (14 files added) took more than 5 s to show its first picture; three warm runs right after took 1.2 s per case. Whether the preparsing slows a cold start is **not measured** (one cold run only; cold opens of 7.9 s were measured before any files were added). To check in step D, with a large folder.
    - **Measured in step D (below):** warm, the build doesn't measurably delay the opened file. Cold, the step D spike's first VLC start had no first picture within 15 s **without autofolder loaded** (one run), so the cold-start slowness is VLC's own.
- **Large folders (measured 2026-11-11, To do 2 step D;** a throwaway spike, then the `build-big` case). A folder of 500 short videos in the headless test VLC, with the opened file the last by date, so 499 files are added and all moved before it. Timings come from `vlc.misc.mdate`, which counts in **1 ms steps** on Windows (every timing came out in whole ms). 1–2 runs each, warm:
  - The build: 37–54 ms in all. Listing and `stat`: 22–32 ms; one `enqueue` of 499 items: 10–17 ms; **499 moves to the front: 1–2 ms**. The playlist was complete and in order at the measuring script's first or second check (every 250 ms): 0.27–0.54 s after VLC started, the file having started 0.02–0.04 s after VLC. So the folder is in place within one or two of autofolder's 300 ms polls.
  - Another script calling `vlc.playlist.current()` every 20 ms never waited more than 3 ms, during the build or the preparsing after it. So the build doesn't hold the playlist long enough to freeze anything; the Qt window itself is a manual check.
  - **The opened file starts no later:** first picture 0.99–1.01 s after start with the build, 0.98–0.99 s without autofolder (the test video has 1 frame/s, so this counts from the first frame after 0). Through UNC: 1.13 s both ways. Playback then kept pace with the clock.
  - `get("playlist")` with 500 items: 0.6–1.3 ms per read, at most 3 ms. autofolder reads it once per 300 ms poll and ~5 times per build: not worth avoiding.
  - **Preparsing:** all 500 items were preparsed within 3.7–3.9 s on the local disk. Through `\\127.0.0.1\C$`, only 352 of 500 after 29 s (~12 per second), still going when the run ended; playback wasn't affected. VLC preparses the same way when it opens a folder itself. With `--no-auto-preparse` the build took the same time and no preparse inputs were created.
  - Through UNC (`\\127.0.0.1\C$`): the build took 899 ms, 875 of them the scan; the folder was in order at the check 1.07 s after VLC started.
- **Opening a folder** (an item whose URI is a folder; measured 2026-11-11):
  - When played, VLC's `directory` module replaces the folder item **in place with a flat list** of its entries (the default `playlist-tree` is off). A subfolder becomes one item, expanded the same way when it plays.
  - The subfolder came first, before names that sort ahead of it. The non-video files of the test folder (`.srt`, `.jpg`, `.txt`, `.nfo`, `.m3u`) and the dot-name `.dot-hidden.mkv` are left out; the attribute-hidden file is kept.
  - The order is roughly natural and case-insensitive, but not quite: `Episode 1, Episode 2, Episode 10, episode 3`.
  - The entries' URIs equal `make_uri` of their paths.
- **Opening an .m3u** (measured 2026-11-11, To do 2 step C, rules-m3u; `playlist.m3u` lists `Episode 1.mkv` and `Episode 2.mkv`, given on the command line): the .m3u item is replaced in place by its entries, a flat list with new ids in list order (3, 4), and the first entry plays. autofolder's 300 ms poll never saw the .m3u item itself playing.
  - With `playlist-tree` on (not the default), the entries would stay under a node. autofolder only looks at the playlist node's direct children, so such nested items aren't matched or de-duplicated (not tested).

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
- Timing of the 8 cases after To do 2 step A: ~20 s per run (measured 2026-11-11, warm).
- Timing of the 16 cases after To do 2 step D: 65.7 s (one run, measured 2026-11-11); `build-big` takes 2.7 s, plus 0.6–0.8 s to make its 500 files (measured in the spike).

## Extensions and dialogs (source: VLC 3.0.24, read 2026-11-11 for To do 3 step B)
Files: modules/lua/extension.c, extension_thread.c, libs/dialog.c, modules/gui/qt/dialogs/extensions.cpp, modules/gui/qt/extensions_manager.cpp (all identical on the 3.0.x branch and the 3.0.24 tag).
- **The startup scan runs the script in a bare Lua state:** `luaL_newstate()` with no standard libraries and no `vlc` table, and `require` replaced by a function that returns nothing. Then it calls only `descriptor()`. So the script's top level may only define functions and call `require` (which gives nil there); `descriptor()` may only build a table. Any library use at the top level makes the scan fail, and the extension is missing from the View menu (logged as "Error loading script").
- **On activation** the script runs again in a fresh state with the standard libraries, `vlc.*` (including `dialog`, `config`, `io`, `msg`, `net`), `vlc.deactivate` and `vlc.keep_alive`, and the module path of `vlclua_add_modules_path` (so `require` of `lua\modules\` works; see "Modules" above). Deactivation runs `deactivate()` and then closes the state, so every activation starts fresh.
- **View menu:** the entry is checkable while the extension is active; clicking an active extension deactivates it.
- **`close()`** is called when the dialog's window is closed (X button or Escape).
- **One dialog per extension** ("Only one dialog allowed per extension!"); the dialog is deleted when the state is closed (`__gc`).
- **Dropdown selection bug:** `add_value(text, id)` appends; the first value added is marked selected. `set_text(text)` before the dialog is first shown makes Qt show the entry with that text, but the combo's change signal is connected only after that, so the selected mark stays on the first value: **`get_value()` then returns the first value until the user picks another one.** `get_text()` returns the shown text in both cases (the `set_text` text, or after a pick the combo's current text). So read a dropdown with `get_text()` when it was pre-set with `set_text`. A `set_text` after the dialog is shown doesn't change the shown entry (Qt's update of a dropdown only adds missing values).
- `get_text()` of a text input returns its current text (Qt syncs it on every change).
- **Labels are always rich text** (`setTextFormat(Qt::RichText)`): `<`, `>` and `&` in a label's text must be escaped, a line break is `<br>` (not `\n`), and `<span style="color:...">` colours it.
- Size hints (`width`, `height`) only call `resize()` when both are given, and the grid layout decides the size anyway; a wide label widens the dialog.
- Widgets are created when the function that made them returns (or at `d:update()`), so a dialog built inside `activate()` is created with all its values and texts.
- **Measured 2026-11-11 (To do 3 step B manual test, the windowed test VLC):**
  - The entry appears in the View menu, and it has a check mark while the dialog is open.
  - A dropdown pre-set with `set_text` shows that entry, and Save without a pick kept it, through `get_text()`. `get_value()`'s wrong answer is still source only: it wasn't run in the real VLC.
  - An escaped `<` in a label shows as `<`, and `<span style="color:...">` colours the text.
  - Escape calls `close()`.
  - Not tested: clicking the menu entry while the dialog is open.

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
- Extensions (3.0.24 tag): https://raw.githubusercontent.com/videolan/vlc/3.0.24/modules/lua/extension.c, .../modules/lua/extension_thread.c, .../modules/lua/libs/dialog.c, .../modules/gui/qt/dialogs/extensions.cpp, .../modules/gui/qt/extensions_manager.cpp
- "Add similar files from folder" add-on: https://store.kde.org/p/1153993
- vlc_autoPlaylist: https://github.com/PhoenixWhitebrow/vlc_autoPlaylist
