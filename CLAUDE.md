# vlc-autofolder

## Goal
Open one video in VLC 3.0.24 on Windows (e.g. a double-click in Explorer), and the other videos in its folder are added to the playlist automatically, in the chosen sort order and around the playing file, so Next and Previous work. The full brief is in docs/spec.md.

Don't build what's under "Later" in docs/todo.md until asked.

## User and environment
- Windows 11; VLC 3.0.24 (its embedded Lua is **5.1**); Windows PowerShell 5.1 (no pwsh). Shell: PowerShell in the VS Code terminal.
- Real paths: docs/local.md (gitignored). VLC isn't on PATH; commands call it by full path.

## Working style
- One to-do per chat, built with the /build-todo skill: `/build-todo N`, or `/build-todo N, step B` for one step of a bigger to-do. Write new to-dos with /add-todo.
- Commit after each working step. End a step with the finish-step skill.

## Build specifics
**Checks** (copy-ready versions in docs/local.md):
- Once per PC: `powershell -ExecutionPolicy Bypass -File tests\setup-tools.ps1` downloads the portable test VLC and luacheck into `tools\` (gitignored; ~10 s measured).
- Fast, after edits:
  - luacheck: `tools\luacheck.exe lua tests` (~0.1 s, measured)
  - PowerShell lint: `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning,Error` (~2 s, measured)
- Once per step: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1` (`-Case NAME` for one case; for several use `-Command "& .\tests\run-tests.ps1 -Case a,b"`, since `-File` passes `a,b` as one name). It runs the portable VLC in `tools\vlc` with no window, one VLC per case, and fails if `%APPDATA%\vlc` changed (~96 s for 23 cases, measured 2026-11-12; rules-late waits 11 s; build-big makes a 500-file folder first; install-script runs the install scripts ~20 times in temp folders, ~7 s; the first run of a day can be slower).
- A test case = an entry in `$cases` in run-tests.ps1 + a driver `tests\lua\intf\test_*.lua` using `require "testlib"` (or a `Check` script block, no VLC: the install checks in `tests\InstallChecks.ps1`). The runner also fails on any `lua error:` log line except the "Interrupted." that ends a script on exit. Shared paths, test media and VLC options: `tests\TestCommon.ps1`.
- Tests run install.ps1 / uninstall.ps1 only with `-VlcDir` (a temp folder or `tools\vlc\portable`); the two install cases are skipped while the user's own VLC is open.
- By hand only, with every VLC closed: `tests\spike-one-instance.ps1` (one-instance hand-over; ~35 s, estimated).
- No screenshot GUI test (see Decisions). The Qt parts are in the manual checklist (docs/manual-test.md, from To do 5).

**Code rules** (from docs/research/vlc-lua-api.md):
- Lua 5.1 only: no `goto`, no `//`, no `utf8` library.
- File access goes through `vlc.io.*` (UTF-8 paths), not plain `io.open`.
- Never catch the error that `vlc.misc.mwait` raises when VLC exits. The script must end then, or VLC can hang on close.
- Extensions: the top level only defines functions and calls `require` (VLC's startup scan runs it with no libraries); read a dropdown pre-set with `set_text` via `get_text()`, not `get_value()`; label text is rich text (escape `<`, `>`, `&`).
- `vlc.playlist.move` only with the playlist node as target (the item becomes first). With an item as target VLC 3.0 picks the place from ids: wrong place or a crash.
- `vlc.strings.make_path`, and VLC itself, drop the server `localhost` (taken as this PC); convert URIs with `core.uri_to_path`, and use `\\127.0.0.1\C$` for UNC tests.
- Tests never touch the real `%APPDATA%\vlc`.
- vlcrc is UTF-8 with BOM and LF line endings: edit it with .NET file APIs, never `Set-Content`, and only while VLC is closed.
- install.cmd / uninstall.cmd only start the `.ps1` files (logic goes there) and keep CRLF line endings (`.gitattributes`).

**Docs to update when behaviour changes:**
- README.md: features, install, sort switch, troubleshooting, limitations, Credits.
- docs/manual-test.md, once it exists.
- docs/research/vlc-lua-api.md, when an API fact is confirmed or turns out wrong (mark it; don't delete it).
- When a README section grows past about a screen, move it into docs/NAME.md and link it from the README.

**Must keep working:** (empty so far)

**Review checklist:** none yet: the built-in code-review skill.

## Status
Now and next: the "Where we are" block at the top of docs/todo.md.

## Decisions
Reasons, who decided, and what was rejected: docs/decisions.md.
- The core is a Lua interface script loaded at startup via the extra-interface setting (not an extension, not a playlist script).
- Tests run the real VLC 3.0.24 with no window, isolated from the real settings; there is no screenshot GUI test.
- The test VLC is the portable zip in `tools\vlc` with a `portable\` folder; test runs always pass `--no-one-instance` and `--no-crashdump`.
- Public on GitHub later.
- install.ps1 adds `luaintf{intf=autofolder}` to vlcrc's `extraintf` (never `lua-intf`), backs up vlcrc before each change and keeps every other byte; uninstall removes only that entry, our files and autofolder.ini.
- The folder sits where the playing item is (in a build the opened file, so at the end), else where its first item is; the user's own items keep their order around it.
- Only a file just opened builds: the playlist's last item (by position, not id), started within 10 s of becoming last (the first play after VLC starts always counts). One copy per folder file.
- A build runs whole, in one poll, at once (measured fast for 500 files); a folder that can't be read is logged, not retried.
- Settings (sort order, video types) live in `autofolder.ini` in `vlc.config.userdatadir()`, shared code in `lua\modules\`; read about every second, a change applied when two reads agree; the interface script never creates the file.
- The settings dialog (View → Auto Folder Playlist settings, an extension) rewrites the whole file on Save and closes; a wrong type is refused in the dialog.
- VLC 3.0's playlist window doesn't show a script's moves: build and re-sort (`place`) delete and re-add the folder items that must change order; items that keep their id keep their order. Never re-added: the playing item, the user's items outside the folder.

## Project docs
- README.md
- docs/spec.md: the original brief
- docs/local.md: this PC's paths and commands; gitignored
- docs/todo.md: the list; docs/todo/: one file per to-do, with a Progress list once it is built in steps
- docs/archive/: finished to-dos' files, read only when a to-do names one
- docs/decisions.md
- docs/research/: one file per topic (vlc-lua-api.md so far)

## Never in tracked files
- Personal paths (the user folder, drive paths): they go in docs/local.md.
- The GitHub login used for pushes: it goes in docs/local.md. This applies to current files only; old commits that hold it are fine.
