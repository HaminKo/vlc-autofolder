# Decisions

One entry per decision, newest first. Each entry has the date and the decision as its heading, then the reason, who decided, and what was rejected and why.

## 2026-11-10: The test VLC is the portable 3.0.24 zip in `tools\vlc`, with a `portable\` folder
- **Reason:**
  - With a `portable` folder next to vlc.exe, VLC 3.0 keeps its settings and Lua user folder there (measured: `vlc.config.userdatadir()` returns it, and `%APPDATA%\vlc` stays unchanged).
  - The zip is pinned by SHA-256, so anyone can recreate the same test VLC with `tests\setup-tools.ps1`.
  - Test runs pass `--no-one-instance --no-one-instance-when-started-from-file`, so they never hand files to the user's own VLC, and `--no-media-library`, so they don't write `ml.xspf`.
- **Who:** the user, accepting Claude's suggestion (To do 1).
- **Rejected:**
  - Copying the installed VLC folder: no download, but it ties the tests to whatever version is installed, and nobody else can reproduce it.
  - The installed VLC with `--config=<temp vlcrc>`: it would still read Lua scripts from the real `%APPDATA%\vlc\lua`.
  - Setting `$env:APPDATA`: VLC finds the folder through the Windows shell API, not the variable (from memory of the source; not tested, since the portable folder made it unnecessary).
- **Test videos:** a raw YUV4MPEG2 video written by PowerShell (2 min, 32x32, 1 frame/s, 185 KB), saved under every video extension. VLC plays it whatever the extension (measured as .mkv and .mp4), so no ffmpeg is needed. Rejected: recording `screen://` with VLC, which would capture the user's screen.

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
- **How it's isolated:** settled in To do 1: see "The test VLC is the portable 3.0.24 zip" above.

## 2026-11-10: The core is a Lua interface script loaded at startup through the extra-interface setting
- **Reason:** it must start with VLC with no menu click.
- **Who:** the user (brief, requirement 1).
- **Rejected:**
  - A Lua extension: extensions can't auto-start in VLC 3.0.
  - A Lua playlist (demux) script: it runs when VLC probes the file and would turn the opened file into a playlist node, so the opened file wouldn't keep playing.
