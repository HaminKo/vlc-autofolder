# To-dos

## Where we are
- Now: To do 6 (re-opened file shown at the bottom)
- Next: To do 4, 5
- Updated: 2026-11-11

The requirements are in [spec.md](spec.md), and the API facts and open questions in [research/vlc-lua-api.md](research/vlc-lua-api.md).

## To do
Next number: 7. Numbers are permanent: never renumber or reuse one; to move a to-do, move its line.

### Now
- To do 6: Playlist window shows a re-opened file at the bottom (medium): docs/todo/06-reopen-at-bottom.md

### Bugs me
- To do 4: Install and uninstall scripts (medium): docs/todo/04-install-scripts.md
- To do 5: README and manual test checklist (small): docs/todo/05-readme-manual-test.md

### Someday
- none yet

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
- Number: the "Next number" (then raise that line by one). The line goes under Someday, unless the user says it bugs them or wants it soon: then under Bugs me where the user says (at most 5 there, so ask which one drops back to Someday), and "Next:" and "Updated:" in "Where we are" change with it.
- Title with size (small / medium / large) and the goal in the user's words.
- Problem / Goal: what is wrong or wanted, with an example. For a bug or research to-do, also what the user has seen (it exists, where, what works) and what is already ruled out.
- Read first: files and functions to look at, outside references.
- Approach: the suggested design, what to reuse.
- Ask the user: open questions, each with a suggested answer.
- Test: what Claude checks, and what the user tests by hand.

Every to-do is its own file from the start, docs/todo/NN-name.md (two-digit number, short name), starting "# To do N: title (size)" and holding the template's parts (later also its Progress list). The list holds one line per to-do and nothing more, so it stays a quick overview: `- To do N: title (size): docs/todo/NN-name.md`. When a to-do is finished, finish-step moves its file unchanged to docs/archive/.
