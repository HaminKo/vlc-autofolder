# Spec: the original brief

The user's brief from 2026-11-10, kept as written. Design choices made since are in [decisions.md](decisions.md); what the VLC 3.0 Lua API really offers is in [research/vlc-lua-api.md](research/vlc-lua-api.md).

---

# Project: VLC "Auto Folder Playlist" for VLC 3.0.24 on Windows 11

## Goal
When I open any single video in VLC (e.g. double-clicking it in File Explorer), VLC should automatically
load every other video in that same folder into the playlist, so Next/Previous work, without me
opening the folder manually or clicking anything in VLC.

## Environment
- Windows 11
- VLC media player 3.0.24 "Vetinari" (Lua scripting API of the 3.0.x branch, NOT 4.x)
- User Lua script folder: %APPDATA%\vlc\lua\ (intf\ and extensions\ subfolders)

## Requirements
1. **Fully automatic.** Must run whenever VLC starts, with no menu activation per session.
   VLC Lua *extensions* can't auto-start, so the core must be a **Lua interface script** (lua/intf/),
   loaded at startup via VLC's "extra interface" setting (extraintf=luaintf, lua-intf=<script name>),
   set either in Tools → Preferences → All → Interface or in vlcrc.
2. **Trigger:** each time a new input starts playing whose path is a local file (file:/// URI).
   Skip non-file inputs (streams, discs, playlist files like .m3u/.xspf).
3. **Scope:** only the folder the opened file is in, with no subfolders.
4. **Files:** every video file in that folder (configurable extension list; default to common video
   formats such as mp4, mkv, avi, mov, wmv, webm, m4v, flv, ts, mpg, mpeg). Ignore subtitles, images, text, etc.
5. **Include files before AND after the opened file** so Previous works too. The opened file must keep
   playing without restarting (or, if a rebuild is unavoidable, resume at the same timestamp).
   Final playlist order must match the chosen sort order, with the opened file in its correct position.
6. **Sort order:** default = date modified (oldest first). Must be switchable without editing code to at least:
   - date modified (oldest → newest / newest → oldest)
   - name, using natural sort (Episode 2 before Episode 10)
   Propose the cleanest way to switch, e.g. a small companion VLC extension (View menu) that writes a
   settings file in vlc.config.userdatadir(), which the interface script reads; or the "Lua interface
   configuration" preference string. Explain the trade-offs before choosing.
7. **No duplicates / no loops.** If I click another item already in the generated playlist, or the
   folder's files are already in the playlist, do nothing. If I open a file from a *different* folder,
   build that folder's playlist instead.
8. Must handle Unicode filenames, spaces, special characters (proper URI encoding via vlc.strings
   helpers), UNC/network paths if possible, and folders with hundreds of files without freezing VLC.
9. Behave sensibly with VLC's "Allow only one instance" and "Enqueue items in one instance mode"
   settings; document what happens in each case.

## Technical notes / things to verify against the 3.0 API
- Directory listing + file times: vlc.net.opendir() and vlc.net.stat() (check that modification_time
  is available in 3.0.24).
- Detecting the current item: vlc.object.input() / vlc.input.item() polled in the intf loop
  (use a short sleep, e.g. vlc.misc.mwait or equivalent, to avoid busy-waiting).
- Adding items: vlc.playlist.enqueue(); reordering: check whether vlc.playlist.move() exists in 3.0
  and works for placing earlier files before the current item.
- Log with vlc.msg.dbg/info so I can debug via Tools → Messages (verbosity 2).

## Deliverables
1. The Lua interface script (main logic).
2. The sort-order switch (companion extension or alternative), if needed.
3. A PowerShell install script that copies files to %APPDATA%\vlc\lua\... and enables the interface
   in vlcrc (back up vlcrc first), plus an uninstall script that reverses it.
4. README: install, how to switch sort order, how to troubleshoot, known limitations.
5. A manual test checklist (open a middle file, first file, last file, Unicode names, switching
   folders, clicking items within the playlist, one-instance mode on/off).

## Process
Ask me clarifying questions before writing code if anything is ambiguous. Confirm the 3.0.x Lua API
details first (check VLC 3.0 source/docs for lua/README and the intf/extension examples) instead of
guessing function names.
