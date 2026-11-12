# To-dos

## Where we are
- Now: To do 3, step B (the sort dialog)
- Next: To do 6, 4, 5
- Updated: 2026-11-11

Next number: 7

The requirements are in [spec.md](spec.md), and the API facts and open questions in [research/vlc-lua-api.md](research/vlc-lua-api.md).

## To do

### 3. Sort-order switch (medium): "Must be switchable without editing code"
In its own file: [todo/03-sort-switch.md](todo/03-sort-switch.md) (two steps: A the settings file and live re-sort, done; B the dialog).

### 6. Playlist window shows a re-opened file at the bottom (medium): "it appeared on the bottom"
- **Problem / Goal:** in the built test folder (16 videos, date order), Ctrl+O on Episode 2.mkv again (To do 3 step A, manual test 8, 2026-11-11):
  - Episode 2 plays, once, and in VLC's own playlist it is 2nd. The rules-refresh case checks this order.
  - The playlist window shows it **at the bottom**.
  - Cause (known): the build moves the new copy into the old copy's place, and VLC 3.0's window doesn't show a script's moves (research/vlc-lua-api.md, "Playlist", `move`).
  - A re-sort had the same problem. It now deletes and re-adds the items instead, and the window was right in 5 sort changes by hand (decisions.md, "A re-sort deletes and re-adds").
- **Read first:**
  - `autofolder.lua`: `build`, `arrange`, `reorder`, `resort` (the re-add pattern, with the target worked out before deleting).
  - `autofolder_core.lua`: `match_items`, `target_order`, `front_moves`.
  - test_settings.lua `live` (how a re-add is checked: new ids).
- **Approach:** in a build, an item the window already shows is never moved. The items that would have to move are deleted and re-added in place, as `resort` does, with the target worked out first.
  - Kept: the playing item (it would restart) and the items already in the right order relative to it. The longest such run stays; `front_moves` already finds it for moves.
  - Probably one shared function for build and re-sort.
- **Ask the user:**
  - Re-add only the items that must move, or the whole folder on every build? *Suggested: only those that must move. On a share VLC re-reads ~12 files/s, so a re-add isn't free.*
  - A folder file the user had added themselves elsewhere in the playlist is moved into the folder by a build (same window problem). Re-add it too, and keep it as the user's? *Suggested: yes. Only item options set when it was added would be lost, which is rare for a local file.*
- **Test:**
  - Claude: rules-refresh, plus checks that every item whose place changed has a new id while the playing copy keeps its id.
  - The user: To do 3 step A manual test 8 again. The window shows Episode 2 2nd.

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
