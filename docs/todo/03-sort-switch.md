# To do 3. Sort-order switch (medium)

"Must be switchable without editing code"

Built in two steps (one chat each). Moved here from [../todo.md](../todo.md) on 2026-11-11.

- **Problem / Goal:** sort by date modified (oldest or newest first) or by name with natural sort (Episode 2 before Episode 10). The default is date modified, oldest first. The video extension list is configurable too (spec.md requirement 4; To do 2 answer 6 left it to this to-do).
- **Read first:** spec.md requirements 4 and 6; research/vlc-lua-api.md (lua-config, `vlc.io`, `userdatadir`, "Lua module paths").
- **Approach** (options as written before the build):
  - A. **Companion extension** (View → Auto Folder Playlist): a dialog with a sort dropdown and the extension list. It writes a settings file in `vlc.config.userdatadir()`; the interface script re-reads it. Pros: switch inside VLC; no restart; the file can also be edited by hand. Cons: a second script to install; the dialog works in the Qt interface only and can only be tested by hand.
  - B. **"Lua interface configuration" preference** (`lua-config`, e.g. `autofolder={sort="name"}`). Cons: Lua syntax in a preference field; a VLC restart; shared with VLC's other Lua interfaces; a typo silently breaks it.
  - C. **Settings file only**, edited by hand. Least code; no switch inside VLC.
- **Answers** (2026-11-11: the user went with all suggestions; decisions.md "Sort-order switch"):
  1. **A, in two steps.** Step A is the settings file with a live re-sort (that is C); step B adds the dialog. Step B can still be dropped after step A.
  2. **A change is applied at once:** within ~1 s of saving, the active folder's items are put in the new order. The playing file keeps playing. A re-sort only reorders; adding and removing files is left to the next file opened.
  3. **Four orders:** date modified oldest first (default), newest first, name A→Z, name Z→A (natural order).
  4. **Newest first, equal dates: name A→Z** (Episode 1 before Episode 2 among files copied together).
  5. **The video types apply at the next file opened**, not to the current playlist; items of a type removed from the list stay until a file from another folder is opened. An empty list means the default list. Types may be separated by spaces or commas, with or without a dot, in any case.
  6. **The settings file** is `autofolder.ini` in VLC's user folder (`%APPDATA%\vlc`): lines `sort=date-oldest` (or `date-newest`, `name-az`, `name-za`) and `extensions=mp4 mkv ...`, `#` or `;` comments. A wrong value gives a warning in Tools → Messages, and that line's default is used. The interface script never creates the file; the dialog or the user does.
- **Test:**
  - Claude: tests for each sort order, and for a settings change picked up while running.
  - The user: edit the file by hand (step A), switch in the dialog (step B), and watch the playlist re-sort.

## Progress
- [x] **Step A: the settings file, four orders, the video types, live re-sort** (2026-11-11)
  - Built (~900 changed lines with docs, measured: 477 in changed files, 423 in new ones; planned 350 without docs):
    - `lua\modules\autofolder_settings.lua` (new): the orders, default video types, parse (BOM, CRLF, `#`/`;` comments, also after a value), format, path, read, write.
    - `autofolder_core.lua`: `sort_files(files, order)` for the four orders; `set_extensions`.
    - `autofolder.lua`:
      - The file is read every ~1 s, and a change is applied when two reads agree.
      - A re-sort deletes and re-adds the script's items, then places them with a target worked out before the deletes.
    - Tests: settings-parse, settings-live (also a deleted item, new ids, a user's item playing) and settings-types; test_core for the orders.
  - The code review fixed 6 of 9 points (see the step's hand-over). Left:
    - A re-sort uses the build's dates.
    - `ascii_lower` exists twice.
    - Two one-line test wrappers.
  - Manual test 3 found that VLC's playlist window doesn't show a script's moves; the re-add above is the fix.
  - Test results:
    - 19 cases pass (82 s, measured).
    - The user's manual tests 1–7, 9 and 10 pass. The window showed every sort change.
    - Test 8 (re-opening a file of the folder, To do 2 behaviour) showed the file at the bottom of the window: To do 6.
  - Measured on the way: `stop()` keeps `current()` at the stopped item (research/vlc-lua-api.md).
  - Plan as written before the build (~350 lines: code ~150, tests ~200):
    - `lua\modules\autofolder_settings.lua` (new, shared with step B's dialog): the orders, the default video list (moved from core), parse, format, path, read.
    - `autofolder_core.lua`: `sort_files(files, order)` replaces `sort_by_date`; `set_extensions(list)`.
    - `autofolder.lua`: reads the file at start and every ~1 s (contents compared: file times count whole seconds); logs a change or warnings once; keeps the last build's files; a sort change re-sorts them with `arrange`.
    - Tests: `test_core` (orders, ties, a custom list); new driver `test_settings.lua` (parse, format, round trip); cases settings-live and settings-ext; a `Settings` field in run-tests.ps1 writes `tools\vlc\portable\autofolder.ini`.
    - Docs: README (switching by hand), research (module paths), decisions.
- [ ] **Step B: the dialog** (View → Auto Folder Playlist)
  - `lua\extensions\autofolder_dialog.lua`: a sort dropdown, a video-types field, Save / Cancel; uses `autofolder_settings`.
  - A load test with a stand-in dialog (catches typos, checks Save writes the file). The real dialog is the user's test.
  - Questions for that chat: the dialog's details (e.g. whether Save closes it).
