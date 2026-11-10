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
- Once per step: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1` (`-Case NAME` for one case). It runs the portable VLC in `tools\vlc` with no window, one VLC per case, and fails if `%APPDATA%\vlc` changed (~3 s with 1 case, measured; ~1.5 s per added case, estimated).
- A test case = an entry in `$cases` in run-tests.ps1 + a driver `tests\lua\intf\test_*.lua` using `require "testlib"`. The runner also fails on any `lua error:` log line except the "Interrupted." that ends a script on exit.
- No screenshot GUI test (see Decisions). The Qt parts are in the manual checklist (docs/manual-test.md, from To do 5).

**Code rules** (from docs/research/vlc-lua-api.md):
- Lua 5.1 only: no `goto`, no `//`, no `utf8` library.
- File access goes through `vlc.io.*` (UTF-8 paths), not plain `io.open`.
- Never catch the error that `vlc.misc.mwait` raises when VLC exits. The script must end then, or VLC can hang on close.
- Tests never touch the real `%APPDATA%\vlc`.
- vlcrc is UTF-8 with BOM and LF line endings: edit it with .NET file APIs, never `Set-Content`, and only while VLC is closed.

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
- The test VLC is the portable zip in `tools\vlc` with a `portable\` folder; test runs always pass `--no-one-instance`.
- Public on GitHub later.

## Project docs
- README.md
- docs/spec.md: the original brief
- docs/local.md: this PC's paths and commands; gitignored
- docs/todo.md; docs/todo/: big to-dos in their own files, with a Progress list
- docs/decisions.md
- docs/research/: one file per topic (vlc-lua-api.md so far)

## Never in tracked files
- Personal paths (the user folder, drive paths): they go in docs/local.md.
- The GitHub login used for pushes: it goes in docs/local.md. This applies to current files only; old commits that hold it are fine.
