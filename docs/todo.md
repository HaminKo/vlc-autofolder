# To-dos

## Where we are
- Now: Before a public release (no to-dos open)
- Next: none
- Updated: 2026-11-14

The requirements are in [spec.md](spec.md), and the API facts and open questions in [research/vlc-lua-api.md](research/vlc-lua-api.md).

## To do
Next number: 9. Numbers are permanent: never renumber or reuse one; to move a to-do, move its line.

### Now
- none

### Bugs me
- none

### Someday
- To do 7: Playlist window sometimes shows a new folder in the wrong order (medium): docs/todo/07-window-order-race.md

## Later, only if the user asks
- Subfolders (recursive).
- Watching the folder for new files while playing.
- Sort settings per folder.
- Other sort orders (size, date created).
- VLC 4.x support.
- Linux and macOS.

## Before a public release
- ~~Run docs/manual-test.md on the installed VLC again if the code changed since its full run (2026-11-13, To do 5).~~ Done 2026-11-14, in part: manual-test.md "Runs" and decisions.md.
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
