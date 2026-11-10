# Decisions

One entry per decision, newest first. Each entry has the date and the decision as its heading, then the reason, who decided, and what was rejected and why.

## 2026-11-10: Public on GitHub later
- **Reason:** a small VLC add-on is useful to others.
- **Who:** the user, accepting Claude's suggestion.
- **Consequence:** personal paths and the GitHub login used for pushes never go in tracked files.
- **Rejected:** staying private-only, because there was no reason to.

## 2026-11-10: Tests run the real VLC 3.0.24 with no window, isolated from the real settings; no screenshot GUI test
- **Reason:**
  - The script runs inside VLC's own Lua 5.1, so only VLC itself is a faithful test runtime.
  - The behaviour is playlist state, which a test script can check exactly.
  - The few Qt parts (sort dialog, one-instance mode) are covered by the manual checklist.
- **Who:** the user, accepting Claude's suggestion.
- **Rejected:**
  - A standalone Lua interpreter with mock `vlc.*` functions: the mocks could disagree with the real 3.0 API.
  - Screenshots of the Qt window: they add little over checking the playlist directly.
- **How it's isolated:** to be settled in To do 1. Probably a portable VLC 3.0.24 in `tools\`, because VLC ignores `$env:APPDATA` (see research/vlc-lua-api.md).

## 2026-11-10: The core is a Lua interface script loaded at startup through the extra-interface setting
- **Reason:** it must start with VLC with no menu click.
- **Who:** the user (brief, requirement 1).
- **Rejected:**
  - A Lua extension: extensions can't auto-start in VLC 3.0.
  - A Lua playlist (demux) script: it runs when VLC probes the file and would turn the opened file into a playlist node, so the opened file wouldn't keep playing.
