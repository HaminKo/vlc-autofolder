# To-dos

## Where we are
- Now: To do 2, step A (trigger, scan, sort, add later files)
- Next: To do 3, 4, 5
- Updated: 2026-11-11

Next number: 6

The requirements are in [spec.md](spec.md), and the API facts and open questions in [research/vlc-lua-api.md](research/vlc-lua-api.md).

## To do

### 2. The interface script (large, built in steps): "When I open any single video, VLC automatically loads every other video in that folder, so Next/Previous work"
- **Problem / Goal:** spec.md requirements 1–8.
  - Example: double-click `Episode 05.mkv` in a folder of 12 episodes. The playlist becomes Episode 01–12 in sort order, and 05 keeps playing without a restart.
- **Read first:** spec.md, research/vlc-lua-api.md (playlist and lifecycle sections, To do 1's answers), decisions.md.
- **Approach:**
  - `lua\intf\autofolder.lua` polls `vlc.playlist.current()` every ~300 ms with `mwait`, never catching its "Interrupted." error.
  - It acts only when the id changes to a `file://` item with a video extension.
  - Pure logic goes in a testable helper module: URI to path, extension filter, natural sort, mtime sort, and the target order.
  - Build:
    - List the folder; keep video files only, no subfolders; stat each for mtime; sort (mtime oldest first for now).
    - Enqueue all missing files in one call.
    - Look up the new ids with `get("playlist")`.
    - ~~Move each one into place around the playing item.~~ **Replaced (To do 1 step B):** VLC 3.0's `move` after an item is broken (wrong place or a crash). Files after the playing one: enqueue in order (appended). Files before it: enqueue, then move each to the front of the playlist node, last one first (decisions.md, 2026-11-11).
  - URI to path: `vlc.strings.make_path` works for local files but drops a UNC server; `make_uri` equals VLC's own URIs (research/vlc-lua-api.md, measured).
  - State: the active folder, and the ids this script manages.
  - Log with the prefix `[autofolder]`: `info` for actions, `dbg` for details.
  - Steps:
    - A: trigger, scan, sort, add later files.
    - B: insert earlier files before the playing one.
    - C: no duplicates, folder switch, guard for playlist files.
    - D: a 500-file folder without freezing, and UNC paths.
- **Ask the user:**
  - A file from a *different* folder starts playing while VLC runs. With default settings this is the common case: Explorer double-clicks reuse the open VLC and append. *Suggested:* remove the previous folder's items this script added, plus the file opened there; keep items you added yourself; then build the new folder.
  - An .m3u/.xspf or a hand-made mixed playlist is playing. *Suggested:* build only when the playing file is the newest item in the playlist and its folder isn't built yet. Then clicking items in your own playlist does nothing.
  - A file from the folder that's already loaded is opened again (VLC appends a duplicate). *Suggested:* keep one copy in its correct place, keep it playing, and add any new files that appeared in the folder since.
  - Hidden files. *Suggested:* skip names starting with `.`. Windows' hidden attribute is **not** visible to Lua (measured in To do 1 step B: `stat` gives the same mode), so attribute-hidden files are included, as when VLC opens a folder itself.
  - Shuffle is on. *Suggested:* still build in sort order; VLC shuffles anyway.
- **Test:**
  - Claude: headless tests per step:
    - middle, first and last file
    - Unicode and special names
    - non-videos and subfolders ignored
    - clicking within the playlist does nothing
    - switching folders
    - duplicate re-open
    - 500 files (timing measured)
  - The user: the matching manual checks in the real VLC.

### 3. Sort-order switch (medium): "Must be switchable without editing code"
- **Problem / Goal:** sort by date modified (oldest or newest first) or by name with natural sort (Episode 2 before Episode 10). The default is date modified, oldest first.
- **Read first:** spec.md requirement 6; research/vlc-lua-api.md (lua-config, `vlc.io`, `userdatadir`).
- **Approach** (options and trade-offs, to choose at build time):
  - A. **Companion extension** (View → Auto Folder Playlist): a dialog with a sort dropdown and the extension list.
    - It writes a settings file in `vlc.config.userdatadir()`. The interface script re-reads it when the file's mtime changes.
    - Pros: switch inside VLC; no restart; can re-sort the current playlist at once; the file can also be edited by hand.
    - Cons: a second script to install; the dialog works in the Qt interface only.
  - B. **"Lua interface configuration" preference** (`lua-config`, e.g. `autofolder={sort="name"}`).
    - Pros: no extra code.
    - Cons: you type Lua syntax into a preference field; it needs a VLC restart; the field is shared with VLC's other Lua interfaces; a typo silently breaks it.
  - C. **Settings file only**, edited by hand.
    - Pros: least code.
    - Cons: no switch inside VLC.
- **Ask the user:**
  - A, B or C? *Suggested: A.* Its settings file also covers C.
  - Apply a change to the current playlist right away (re-sort in place, no restart)? *Suggested: yes.*
  - Also offer name Z→A? *Suggested: yes; it costs almost nothing.*
- **Test:**
  - Claude: tests for each sort order, and for a settings change picked up while running.
  - The user: switch in the dialog and watch the playlist re-sort.

### 4. Install and uninstall scripts (medium): "Copies files and enables the interface in vlcrc (back up vlcrc first), plus an uninstall script that reverses it"
- **Problem / Goal:** a one-command install and uninstall in Windows PowerShell 5.1.
- **Read first:** research/vlc-lua-api.md ("This PC's VLC": vlcrc is UTF-8 with BOM and LF line endings, with sections) and To do 1's chain-syntax answer.
- **Approach:**
  - `install.ps1`:
    - Stop with a message if vlc.exe is running.
    - Copy `lua\` into `%APPDATA%\vlc\lua\`.
    - Back up vlcrc with a timestamp.
    - Add `luaintf{intf=autofolder}` (or `luaintf` + `lua-intf=autofolder`) to `extraintf` in `[core]`, keeping existing entries.
    - Keep the BOM and LF line endings.
    - If vlcrc doesn't exist yet, ask the user to start and close VLC once.
  - `uninstall.ps1`: remove our files and only our vlcrc changes.
  - Both take a `-VlcDir` parameter, so tests can run them against a copy.
- **Ask the user:**
  - Uninstall: restore the backup, or remove only our changes? *Suggested: only our changes; you may have changed other settings since.*
  - `lua-intf` already used by another script? *Suggested: use the chain syntax (To do 1 measured that it works); otherwise stop with a message.*
- **Test:**
  - Claude: install and uninstall against a copied vlcrc in a temp folder; the diff shows only our lines; encoding is unchanged; PSScriptAnalyzer is clean.
  - The user: a real install, double-click a video, then uninstall.

### 5. README and manual test checklist (small): "Install, how to switch sort order, troubleshoot, known limitations; a manual test checklist"
- **Problem / Goal:** spec.md deliverables 4 and 5, plus requirement 9: document what happens with one-instance mode on/off and enqueue mode on/off.
- **Read first:** spec.md; the README as the earlier to-dos left it; research/vlc-lua-api.md (one-instance).
- **Approach:**
  - README: install, sort switch, troubleshooting (Tools → Messages, verbosity 2, filter `autofolder`), known limitations, and a one-instance behaviour table filled from real tests (the headless results are in research/vlc-lua-api.md, "One-instance mode").
    - Troubleshooting must say: a double-click only reaches VLC when VLC is the default app for the video type (on the dev PC, Windows Media Player was). A VLC opened from the Start menu doesn't receive double-clicks; each starts its own VLC (measured).
  - `docs/manual-test.md`:
    - middle, first and last file
    - Unicode names
    - switching folders
    - clicking items within the playlist
    - one-instance on/off and enqueue on/off
    - opening an .m3u
    - a network share
    - a large folder
- **Ask the user:** none yet.
- **Test:**
  - Claude: every README step is checked against the code.
  - The user: runs the checklist once.

## Later, only if the user asks
- Subfolders (recursive).
- Watching the folder for new files while playing.
- Sort settings per folder.
- Other sort orders (size, date created).
- VLC 4.x support.
- Linux and macOS.

## Before a public release
- Pick a license and add a LICENSE file. Ask the user. *Suggested: MIT, or GPL-2.0-or-later to match VLC.*
- Search all tracked files for the "Never in tracked files" list in CLAUDE.md. If old commits hold any of it, publish a new repo with one clean commit instead of rewriting history.
- A fresh subagent that hasn't seen the project checks README.md and the docs it links against the code. It only reports; the user decides the fixes.
- A screenshot in the README (the playlist after opening one file, and the sort dialog).
- Start CHANGELOG.md (Keep a Changelog: Unreleased first, then versions newest first) with the first version.

## Writing a to-do
- Title with size (small / medium / large) and the goal in the user's words.
- Problem / Goal: what is wrong or wanted, with an example. For a bug or research to-do, also what the user has seen (it exists, where, what works) and what is already ruled out.
- Read first: files and functions to look at, outside references.
- Approach: the suggested design, what to reuse.
- Ask the user: open questions, each with a suggested answer.
- Test: what Claude checks, and what the user tests by hand.

Each to-do starts as an entry in this list. When one grows past ~10 lines, offer to move it into its own file, docs/todo/NN-name.md.
