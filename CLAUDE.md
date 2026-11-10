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
**Checks** (the commands become real in To do 1; copy-ready versions in docs/local.md):
- Fast, after edits:
  - luacheck: `tools\luacheck.exe lua tests` (~1 s, estimated)
  - PowerShell lint: `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning,Error` (~5–10 s, estimated)
- Slow, once per step: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1`. It runs the real VLC with no window, isolated from the real settings (~20–40 s, estimated).
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
- Public on GitHub later.

## Project docs
- README.md
- docs/spec.md: the original brief
- docs/local.md: this PC's paths and commands; gitignored
- docs/todo.md
- docs/decisions.md
- docs/research/: one file per topic (vlc-lua-api.md so far)

## Never in tracked files
- Personal paths (the user folder, drive paths): they go in docs/local.md.
- The GitHub login used for pushes: it goes in docs/local.md. This applies to current files only; old commits that hold it are fine.
