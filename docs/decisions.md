# Decisions

One entry per decision, newest first. Each entry has the date and the decision as its heading, then the reason, who decided, and what was rejected and why.

## 2026-11-11: The folder takes the place of its first item; the user's own items keep theirs
- **Rule:** after a build, the playlist is: the user's items that were before the folder's first item (normally the opened file), then the folder in sort order, then all other items in their order. The fewest moves to the front reach that order; that can move the user's items too.
- **Reason:** the user's items stay where they put them, and the folder goes where the opened file landed (at the end, since a double-click appends), as when VLC opens a folder itself (it expands the folder in place). With the folder first, VLC would play on into unrelated items after the last episode, and the user's list would be reordered.
- **Who:** the user, accepting Claude's suggestion (To do 2 step B questions).
- **Rejected:** the folder at the front of the playlist with the user's items after it (the step B plan written in step A): see Reason. It also needs a move for every folder item as soon as any user item is in the playlist.

## 2026-11-11: A folder is built only for a file that was just opened
- **Rule:** the playing item triggers a build only when it was added after the previous file started playing, plays straight away, and is the newest item in the playlist. Playing an item that was already there (a click, Next/Previous, an .m3u's entries, several files opened at once) never builds.
- **Reason:** the double-click, Open File and drag-onto-window cases all add one item and play it at once; a hand-made playlist must stay as the user made it.
- **Who:** the user, accepting Claude's suggestion (To do 2 questions).
- **Rejected:**
  - "The playing item is the newest one" alone (the to-do's first suggestion): stepping with Next to the last item of a hand-made playlist would build that item's folder and rearrange the list.
  - "Added since the previous poll": racy, since VLC can add an item and start it hundreds of ms (up to ~6 s, measured in To do 1) apart.

## 2026-11-11: Folder switch, duplicates and deleted files
- **Rule:**
  - A file from another folder: remove the old folder's items the script added plus the file opened there; keep the user's own items; build the new folder.
  - A folder file already in the playlist is never added twice: one copy stays in its place (the playing one, if it's a re-opened duplicate), and files that appeared in the folder since are added.
  - Items whose file was deleted from the folder are removed when the folder is built again.
- **Reason:** VLC appends on every double-click and never clears, so without removal the playlist grows without end; spec requirement 7 asks for no duplicates. A deleted file would make VLC show a "can't open" error.
- **Who:** the user, accepting Claude's suggestions (To do 2 questions).
- **Rejected:** keeping old folders (the playlist grows; Next runs into the old folder); clearing the whole playlist (it would remove the user's own items).

## 2026-11-11: The folder logic places files only by moving them to the front of the playlist node
- **Reason:** VLC 3.0's Lua `playlist.move(id, target)` with an item as target computes the new place from item ids, not positions: wrong places, and a crash when the index falls out of range (measured; research/vlc-lua-api.md, "Playlist"). Moving into the playlist node (the item becomes first) works and keeps playback and Next/Previous right (measured).
- **How:** enqueue the files after the playing one in order (appended); enqueue the files before it, then move each to the front, last one first.
  - **Since To do 2 step B:** all missing files are enqueued in one call in sort order, then `autofolder_core.front_moves` gives the fewest moves to the front that reach the wanted order (the entry above). This also keeps the user's items before the folder, which the first "How" would have split from it.
- **Who:** Claude, forced by the To do 1 step B measurement; the user accepted it with the To do 2 plan (2026-11-11).
- **Rejected:**
  - `move` after an item: wrong place or a crash.
  - `vlc.playlist.sort`: it reorders the user's whole playlist and has no natural or date-modified order.
  - Deleting and re-adding the playing file in the right place: playback would restart.

## 2026-11-11: Test VLCs also pass `--no-crashdump` and `--no-sub-autodetect-file`
- **Reason:**
  - A crashing test VLC wrote a crash dump into the real `%APPDATA%\vlc\crashdump`, despite the portable folder, and the next VLC start would ask to send it (measured). `--no-crashdump` (read by vlc.exe itself) stops that.
  - With `Episode 1.srt` auto-loaded and no video output, the headless VLC took ~6 s to stop Episode 1.mkv, which made switch tests flaky (measured).
- **Who:** Claude, while fixing the failures in To do 1 step B; reported to the user at hand-over.
- **Rejected:**
  - Deleting new crash dumps after each run: the tests would then write into the real folder on purpose.
  - Renaming or removing `Episode 1.srt`: it's there to test that non-videos are ignored.

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
