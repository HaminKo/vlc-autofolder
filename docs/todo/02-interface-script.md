# To do 2. The interface script (large)

"When I open any single video, VLC automatically loads every other video in that folder, so Next/Previous work"

Built in four steps (one chat each). Moved here from [../todo.md](../todo.md) on 2026-11-11.

- **Problem / Goal:** spec.md requirements 1–8.
  - Example: double-click `Episode 05.mkv` in a folder of 12 episodes. The playlist becomes Episode 01–12 in sort order, and 05 keeps playing without a restart.
- **Read first:** spec.md, research/vlc-lua-api.md (playlist and lifecycle sections, To do 1's answers), decisions.md.
- **Approach:**
  - `lua\intf\autofolder.lua` polls `vlc.playlist.current()` every ~300 ms with `mwait`, never catching its "Interrupted." error.
  - It acts only when the id changes to a `file://` item with a video extension.
  - Pure logic goes in a testable helper module, `lua\intf\modules\autofolder_core.lua`: URI to path, extension filter, natural sort, the folder scan, mtime sort, and (step B) the target order.
  - Build:
    - List the folder; keep video files only, no subfolders; stat each for mtime; sort (mtime oldest first for now; equal times in natural name order).
    - Enqueue all missing files in one call.
    - Look up the new ids with `get("playlist")`.
    - ~~Move each one into place around the playing item.~~ **Replaced (To do 1 step B):** VLC 3.0's `move` after an item is broken (wrong place or a crash). Files after the playing one: enqueue in order (appended). Files before it: enqueue, then move each to the front of the playlist node, last one first (decisions.md, 2026-11-11).
    - Step B generalizes this: ~~the folder's items are put at the front of the playlist, in order, with the fewest moves to the node; items the user added stay after them.~~ **Replaced (step B questions):** the folder takes the place of its first item (normally the opened file); the user's items before it stay before it, the others after it. Reached with the fewest moves to the node (decisions.md, 2026-11-11).
  - URI to path: own conversion for local and UNC URIs (`decode_uri`, then the prefix); `vlc.strings.make_path` drops a UNC server. `make_uri` equals VLC's own URIs (research/vlc-lua-api.md, measured).
  - Paths are compared by a key: `/` as `\`, ASCII letters lower-cased (Windows paths ignore case).
  - State: the active folder, and the ids this script manages.
  - Log with the prefix `[autofolder]`: `info` for actions, `dbg` for details.
- **Ask the user** (answered 2026-11-11: the user went with all suggestions):
  1. A file from a *different* folder starts playing while VLC runs (the common case: Explorer double-clicks reuse the open VLC and append). **Remove the previous folder's items this script added, plus the file opened there; keep items the user added; then build the new folder.**
  2. When a build starts. **Only for a file that was just opened:** added after the previous file started playing, playing straight away (double-click, Open File, drag onto the window), and the newest item. Playing anything already in the playlist never builds: clicking an item, Next/Previous, the entries of an .m3u, several files opened at once. Rejected: "the newest item" alone, because stepping with Next to the last item of a hand-made playlist would build that item's folder and rearrange the list.
  3. A folder file already in the playlist (e.g. the same episode double-clicked again: VLC appends a copy). **Never add a folder file twice: keep one copy in its place and playing, add files that appeared since, and remove items whose file was deleted** (VLC would show a "can't open" error on them).
  4. Hidden files. **Skip names starting with `.`.** Windows' hidden attribute is not visible to Lua (measured in To do 1 step B), so attribute-hidden files are included, as when VLC opens a folder itself. A dot-name the user opens still builds its folder (the opened file is placed by its own date).
  5. Shuffle is on. **Build in sort order anyway; VLC shuffles playback itself.**
  6. Video extensions until To do 3 makes them configurable. **mp4 mkv avi mov wmv webm m4v flv ts mpg mpeg, plus m2ts mts 3gp ogv vob**, case-insensitive. Any other type does nothing.
  7. Equal dates modified (files copied together). **Natural name order among them.**
- **Test:**
  - Claude: headless tests per step:
    - middle, first and last file
    - Unicode and special names
    - non-videos and subfolders ignored
    - clicking within the playlist does nothing
    - switching folders
    - duplicate re-open
    - 500 files (timing measured)
  - The user: the matching manual checks, in the portable test VLC with a window until To do 4 installs the script.

## Progress
- [x] **Step A: trigger, scan, sort, add later files** (done 2026-11-11; tested by the user)
  - Planned ~450 lines; built ~520 (code and tests).
  - Built:
    - `lua\intf\modules\autofolder_core.lua`:
      - `uri_to_path`: own conversion for local, UNC and `file://localhost/C:/` URIs.
      - `split_path` (folder keeps its trailing backslash, so a drive root works), `path_key` (ASCII-only lower-casing, `/` as `\`), `is_video` (the 16 extensions from answer 6).
      - Natural order: a character walk, numbers by value, ASCII letters ignoring case, ties by bytes. String comparisons go byte by byte, since Lua's `<` uses the C locale.
      - `scan_folder` (`opendir` + `stat`; files only, no `.` names), `sort_by_date` (mtime, then natural name).
    - `autofolder.lua`:
      - Polls `current()` every 300 ms. It acts when the id changes to an item it didn't add, a `file://` video whose folder isn't the one built last.
      - It scans and sorts the folder, enqueues the files after the playing one in one call, and marks the new ids (ids above the old maximum, matched by URI) as managed.
      - A dot-named opened file is placed by its own `stat`; any other miss is only logged, to avoid adding the file twice.
      - Each poll runs in `pcall`, so a bug is logged with `vlc.msg.err` without stopping the script; `mwait` stays outside the `pcall`.
    - Tests:
      - `test_core.lua` (the helpers inside the real VLC) and `test_build.lua`.
      - Cases build-first, build-middle (the Japanese name), build-last and build-dot. Each checks the order, that the opened file is still playing and started once, and that clicking the last item or the opened file changes nothing.
    - testlib: `run()` repeats `vlc.misc.quit()` every 0.5 s until VLC closes. run-tests.ps1 also allows testlib's "Interrupted.". The smoke case waits up to 10 s for playback.
  - Found (research/vlc-lua-api.md):
    - `current()` returns the new id before VLC creates the input, so the build runs while the file is still opening, and the preparsing of the added files runs alongside it.
    - An early `vlc.misc.quit()` is lost ("no exit handler"): it hung the core case in 5 of 6 runs before the fix.
    - `gotoitem` plays an item, and `nb_played` is 1 after one start.
  - Tests:
    - luacheck and PSScriptAnalyzer clean; run-tests.ps1 passes, 8 cases in ~20 s (measured, warm).
    - The first run of the day failed the smoke case once (cold start, over 5 s to the first picture); fixed in the test, see step D.
    - The user, in the portable test VLC with a window (`hash # sign.mkv`): 12 items in date order, playback not restarted, Next and a click changed nothing, one build line in the log.
  - Review (code-review, medium): 10 findings, 5 fixed (natural order when one name's text is a prefix of the other's, a possible duplicate of the playing file, `file://localhost/C:/` URIs, a dead "Interrupted." branch, an index lookup).
    - Moved to step C: the cleared-playlist gap. Moved to step D: no retry of an unreadable folder.
    - Left: a race with a simultaneous hand-over, and the wider "Interrupted." allowance in the runner (the "done" line still guards it).
    - One finding was wrong: `vlc.msg.err` does log as `lua error:`.
  - Next: step B adds the earlier files (done, see below).
- [x] **Step B: insert earlier files before the playing one** (done 2026-11-11; tested by the user)
  - Planned ~150 lines; built ~220 (code, tests and runner).
  - Choice (the user, step B questions): the folder takes the place of its first item (normally the opened file); the user's items before it stay before it, the others after it. Rejected: the folder at the front with the user's items after it (decisions.md, 2026-11-11).
  - Built:
    - `autofolder_core.lua`: `target_order` (the wanted order of the playlist's ids) and `front_moves` (the fewest moves to the front that reach it: the longest end part already in order stays, the rest is moved, last one first). Pure functions on id lists.
    - `autofolder.lua`: `build` enqueues all missing folder files in one call in sort order; `enqueue` sets each file's id (matched by URI); `arrange` moves to the playlist node only and logs a failed move. Log line: `folder X: 16 videos; added 12 before and 3 after NAME; 12 moves`.
    - Tests:
      - `test_core`: 7 arrangements (in order, opened in the middle or last, user items before or inside the folder, a missing id, empty); each replays the moves and checks the result and the move count.
      - `test_build`: expects the whole folder; Previous plays the file before the opened one and changes nothing. New case build-user: the driver enqueues `summer.mkv` (another folder), then opens `Episode 1.mkv` with `playlist.add`, as a double-click into a running VLC.
      - `run-tests.ps1`: a `Config` field adds fields to a driver's config table; the log patterns include the exact move counts (0, 12, 15, 15, 3).
  - Found (research/vlc-lua-api.md): moves in the build poll keep the opened file playing (same id, started once) and Previous right. The build doesn't always run before VLC creates the opened file's input: in this step's runs the input came first, ~300 ms earlier.
  - Tests:
    - luacheck and PSScriptAnalyzer clean; run-tests.ps1 passes, 9 cases in ~31 s (measured, twice).
    - The user, in the portable test VLC with a window: `hash # sign.mkv` gave the 16 videos in date order, playing in 5th place, Previous and Next right, one build line with 4 moves; `summer.mkv` enqueued, then Open File on `Episode 1.mkv`: summer.mkv stayed first, then the folder, 3 moves.
  - Review (code-review, medium): 10 findings, no code fix needed; the README and decision docs it flagged were updated.
    - Moved to step C: folder files already in the playlist are enqueued again (the old copy counts as a user item); user items after the playing file go behind the folder (only with step A's trigger; step C's "just opened" rule leaves none after it).
    - Moved to step D: hundreds of moves in one poll; `arrange` reads the playlist a third time per build (enqueue's snapshot could be reused).
    - Left: a file whose URI VLC writes differently from `make_uri` gets no id and stays at the end (only a warning); measured equal for every test name. A `]]` in the test folder path would break the `Config` string.
  - Next: step C, the playlist rules: the "just opened" trigger, folder switch, duplicates and the refresh, deleted files.
- [ ] **Step C: the playlist rules (answers 1–3)** (~300 lines)
  - The "just opened" trigger, folder switch, no duplicates and the refresh, removal of deleted files, .m3u and several files opened at once.
  - The refresh also fixes a step A gap: after the playlist was cleared, opening another file from the folder built last adds nothing (the folder still counts as built).
  - Tests: switching folders, duplicate re-open, clicking within the playlist, an .m3u, several files on the command line.
- [ ] **Step D: a 500-file folder without freezing, and UNC paths** (~150 lines)
  - Timing measured; if VLC stalls, spread the work over several polls. UNC via `\\localhost\C$`; the effect of `auto-preparse` on hundreds of items.
  - A folder that can't be read (a share that is briefly offline) is only logged, not retried; decide whether to retry it.
  - Also measure whether the build slows the start of the opened file: the build runs before VLC creates its input, and the preparsing of the added files runs alongside the opening (step A finding, research/vlc-lua-api.md "Playlist"). If it does, build only once the opened file plays.
