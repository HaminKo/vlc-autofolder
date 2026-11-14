# Manual test checklist

The parts the automated tests can't reach: Explorer double-clicks, drag and drop, the Open dialog, the settings dialog, the playlist window, VLC's one-instance settings, and install on your own VLC. Run it once before a release, and after a change to any of these. About 40 minutes (estimated).

- It uses your installed VLC 3.0.24 with autofolder installed. The test videos are in `%TEMP%`, not your own; they show up in VLC's recent-media list.
- Commands are for Windows PowerShell, run in the project folder (VS Code's terminal opens there).
- **Playlist:** View → Playlist (Ctrl+L). **Messages:** Tools → Messages (Ctrl+M), Verbosity 2, and `autofolder` in its Filter box; it shows the lines quoted below (the numbers in ms vary). It shows only what happens after it is opened, so a step that starts VLC with a file is checked in the playlist only; open Messages right after such a step.
- **Into the open VLC:** to open a file in a VLC that is already open, run the step's command (it copies the file's path), then in VLC Media → Open File (Ctrl+O), Ctrl+V in the file name box, Enter. This works whatever the one-instance settings are (a double-click may open a second VLC: section 10, and step 0.6 for when it always does), and a file dropped onto the playlist list is only added, not played (5.2 drops onto the video picture).
- **Messages** is small and stops scrolling once you scroll or select in it: make it bigger, and press Ctrl+End in it before reading.
- Each section says where it starts. "Close VLC" means every VLC window.
- Write down every difference from "See", with the section and step number.

## 0. Prepare
1. Close VLC. This prints nothing when no VLC runs:
   ```powershell
   Get-Process vlc -ErrorAction SilentlyContinue
   ```
2. Make the test videos (about 5 s; it also runs one automated case and ends with `1 case(s), 0 failure(s), ...`). Don't run the automated tests while your VLC is open: they fail when `%APPDATA%\vlc` changes. Every test run deletes and rebuilds the test folder, and only this case makes the 500-video folder: after any other run, do this step again. Once per PC (there's no `tools\` folder yet, e.g. in a fresh clone), first download the test VLC and luacheck:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tests\setup-tools.ps1
   ```
   Then:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tests\run-tests.ps1 -Case build-big
   ```
3. Open the media folder in Explorer, View → Details, sorted by Date modified:
   ```powershell
   explorer "$env:TEMP\vlc-autofolder-tests\media"
   ```
   Its 16 videos, oldest first (each a 2-minute grey picture): `Episode 10.mkv`, `Episode 2.mkv`, `Episode 1.mkv`, `episode 3.MP4`, `hash # sign.mkv`, `percent 100% and %20 literal.mkv`, `a & b.mkv`, `[Group] Title [1080p].mkv`, `it's here.mp4`, `comma, here.avi`, `plus+equals=semi;colon.webm`, `café.mkv`, `日本語.mkv`, `🎬 clip.mp4`, `double  space.mov`, `attribute-hidden.mkv` (Explorer hides it). Never in the playlist: `.dot-hidden.mkv` (Explorer shows it, between `double  space.mov` and `attribute-hidden.mkv`: a leading dot doesn't hide a file in Windows), `Episode 1.srt`, `cover.jpg`, `notes.txt`, `info.nfo`, `playlist.m3u` and the folder `Season 2`.
4. Make VLC the default app for `.mkv`: Settings → Apps → Default apps, search `.mkv`, pick VLC media player. (Or use right-click → Open with → VLC media player wherever this list says double-click: the same command.) The list double-clicks only `.mkv` files.
5. The settings at their defaults: this prints `False` (no settings file), or View → Auto Folder Playlist settings in VLC shows "Date modified, oldest first" and the default video types.
   ```powershell
   Test-Path "$env:APPDATA\vlc\autofolder.ini"
   ```
6. VLC's own files are all one version. This prints `3.0.24` three times; another version on any line means an update didn't replace everything (then double-clicks never reach an open VLC: reinstall VLC 3.0.24, leaving "Delete preferences and cache" unticked):
   ```powershell
   foreach ($f in 'vlc.exe', 'libvlc.dll', 'libvlccore.dll') { '{0}: {1}' -f $f, (Get-Item "$env:ProgramFiles\VideoLAN\VLC\$f").VersionInfo.FileVersion }
   ```

## 1. Install, or update
1. VLC closed. Double-click `install.cmd` in the project folder.
   See: `Copied 4 files to ...`, then `vlcrc: extraintf already starts autofolder (no change)` (an update) or `Backed up vlcrc to ...` and `vlcrc: added luaintf{intf=autofolder} to extraintf` (a first install), then `Installed.` in green.
2. After a first install only: vlcrc differs from the backup the install made only in the extraintf line.
   ```powershell
   $baks = @(Get-ChildItem "$env:APPDATA\vlc\vlcrc.autofolder-*.bak" | Sort-Object Name); Compare-Object (Get-Content $baks[-1].FullName) (Get-Content "$env:APPDATA\vlc\vlcrc")
   ```
   See: two lines, `#extraintf=` (or your old extraintf line) with `<=` and the line with `luaintf{intf=autofolder}` with `=>`.

## 2. One file: the middle and the first
1. VLC closed. In the media folder, double-click `Episode 1.mkv`.
   See: VLC starts and plays it. The playlist holds the 16 videos in the order of 0.3, Episode 1.mkv third and playing, and none of the "never" files.
2. Open Messages. See: no `[autofolder]` line yet (the build was before the window opened).
3. Press Previous (P): Episode 2.mkv plays. Next twice (N): Episode 1.mkv, then episode 3.MP4. The playlist doesn't change.
4. Close VLC. Double-click `Episode 10.mkv`.
   See: the same 16 videos, Episode 10.mkv first and playing. Open Messages.

## 3. Clicks, Next and Previous
Continuing from 2.4.
1. Double-click `hash # sign.mkv` in the playlist. See: it plays; still 16 items; no new `folder` line.
2. Press Next 11 times, up to `attribute-hidden.mkv`. See: each file plays, with no "Your input can't be opened" message. Still 16 items.
3. Press Previous 3 times. See: the files before it play in order; nothing changes.

## 4. The same folder again, your own item, another folder
Start: close VLC, double-click `Episode 1.mkv`, open Messages and keep it open through 5.2.
1. Open `Episode 2.mkv` in this VLC (see "Into the open VLC"):
   ```powershell
   "$env:TEMP\vlc-autofolder-tests\media\Episode 2.mkv" | Set-Clipboard
   ```
   See: Episode 2.mkv plays in this VLC. Still 16 items, each once, Episode 2.mkv second. Messages: `folder ...\media\: 16 videos, 1 before and 14 after Episode 2.mkv; added 0, ...`.
2. In the playlist, right-click an empty spot → Add File..., go to the media folder's parent `vlc-autofolder-tests` and open `summer.mkv`.
   See: summer.mkv is added at the end and doesn't play; Episode 2.mkv keeps playing; nothing else changes.
3. Open `Season 2\Episode 1.mkv` in this VLC:
   ```powershell
   "$env:TEMP\vlc-autofolder-tests\media\Season 2\Episode 1.mkv" | Set-Clipboard
   ```
   See: it plays. The playlist is summer.mkv, then Season 2's Episode 1.mkv (playing) and Episode 2.mkv. Messages: `left folder ...\media\: ...` and `folder ...\Season 2\: 2 videos, ...`.

## 5. Names from the Open dialog, a drop and a double-click
Continuing from 4.3. Each file must be in the playlist once: an opened file that autofolder doesn't recognise shows up twice.
1. In VLC, Media → Open File (Ctrl+O), go to the media folder and open `café.mkv`.
   See: it plays. The playlist is summer.mkv, then the 16 videos with café.mkv twelfth, each once. The Season 2 videos are gone.
2. Drag `🎬 clip.mp4` from Explorer onto VLC's video picture (not onto the playlist list).
   See: it plays; still summer.mkv and the 16 videos, 🎬 clip.mp4 fourteenth, once. Messages: a `folder` line with `added 0`.
3. Close VLC. In Explorer, double-click `日本語.mkv`. See: VLC starts and plays it; the 16 videos, 日本語.mkv thirteenth, once.

## 6. Several files and an .m3u
1. Close VLC. In the media folder select `Episode 1.mkv`, `Episode 2.mkv` and `Episode 10.mkv` (Ctrl+click) and press Enter.
   See, with the defaults: one VLC window with the 16 videos, the file it got last playing (on the dev PC `Episode 10.mkv`, 2026-11-13), also after Next. Windows starts one VLC per file and they hand their files to the first, so each counts as opened. With "Use only one instance when started from file manager" off: one VLC per file, each with the 16 videos.
2. Close VLC. Start VLC from the Start menu and drag the same 3 files together onto its window. See: the 3 files only, also after Next.
3. Close VLC. Start VLC from the Start menu and drag `playlist.m3u` onto its window.
   See: Episode 1.mkv plays; the playlist holds only the .m3u's 2 entries (Episode 1.mkv, Episode 2.mkv), also after Next.

## 7. The settings dialog
1. Close VLC. Double-click `Episode 1.mkv`. See: the 16 videos in date order. Open Messages and keep it open through section 9.
2. View → Auto Folder Playlist settings.
   See: a window "Auto Folder Playlist": sort order "Date modified, oldest first", video types the default list, and a line with the default list.
3. Pick "Name, A to Z" and click Save.
   See: the dialog closes. Within about 2 s the playlist window shows the videos by name, among them Episode 1.mkv, Episode 2.mkv, episode 3.MP4, Episode 10.mkv in that order. Episode 1.mkv plays on without restarting (its time keeps counting). Messages: `dialog: saved sort name-az ...`, `settings: sort name-az ...`, `re-sorted by name-az ...`.
4. Open the dialog again. See: "Name, A to Z". Type `mp4 mkv x.y` as video types and click Save.
   See: the dialog stays open with the note `Not a file type: "x.y". ...`; the playlist doesn't change.
5. Click Cancel. See: the dialog closes; nothing changes.
6. Open the dialog again, pick "Date modified, oldest first", empty the video types, click Save. See: within about 2 s the playlist is back in date order.

## 8. A large folder, and the last file
Continuing from 7.6 (VLC and Messages open).
1. Open `big\Show S01E028.mkv`, the newest of the 500, in this VLC:
   ```powershell
   "$env:TEMP\vlc-autofolder-tests\big\Show S01E028.mkv" | Set-Clipboard
   ```
   See: VLC plays it as quickly as any file. The playlist has 500 videos (the media folder's are gone), Show S01E028.mkv last and playing. VLC stays responsive while the lengths fill in. Messages: `left folder ...\media\: ...` and `500 videos, 499 before and 0 after Show S01E028.mkv; added 499, ...`.
2. Press Previous. See: Show S01E055.mkv plays.

## 9. A network path and a mapped drive
Through this PC's own admin share (no real network share needed). With a real share, do step 1 with a folder there too.
Continuing from 8.2 (VLC and Messages open).
1. Open `Episode 1.mkv` through the share in this VLC:
   ```powershell
   ('\\127.0.0.1\{0}${1}\vlc-autofolder-tests\media\Episode 1.mkv' -f $env:TEMP.Substring(0, 1), $env:TEMP.Substring(2)) | Set-Clipboard
   ```
   See: VLC plays it at once; the playlist has the 16 videos in date order (the 500 are gone); their lengths appear gradually. Messages: `folder \\127.0.0.1\C$\...\media\: 16 videos, ...`.
2. Map a drive to the same share (if Z: is taken, use another free letter here and below):
   ```powershell
   net use Z: \\127.0.0.1\C$
   ('Z:{0}\vlc-autofolder-tests\media\Episode 2.mkv' -f $env:TEMP.Substring(2)) | Set-Clipboard
   ```
   Open it in this VLC (Ctrl+O, Ctrl+V, Enter).
   See: VLC plays it. The playlist has the 16 videos once, now from Z: (the `\\127.0.0.1` ones are gone: another folder to autofolder). Messages: `folder Z:\...\media\: 16 videos, ...`.
3. Close VLC and remove the drive:
   ```powershell
   net use Z: /delete
   ```

## 10. One instance and enqueue mode
The three settings are in Tools → Preferences (Show settings: Simple) → Interface, under "Playlist and Instances". Note their values first; the defaults are: "Allow only one instance" off, "Use only one instance when started from file manager" on, "Enqueue items into playlist in one instance mode" off. A change applies from the next VLC start. The table "When VLC is already open" in [guide.md](guide.md#when-vlc-is-already-open) must match what you see. If every double-click opens a new VLC whatever the settings, check step 0.6: on the dev PC that was the cause (2026-11-13, research/vlc-lua-api.md "One-instance mode").
1. **Defaults, VLC started by a double-click.** VLC closed. Double-click `Episode 1.mkv`, then `Season 2\Episode 1.mkv`.
   See: one VLC window; the second file plays in it; the playlist holds Season 2's 2 videos. Close VLC.
2. **Defaults, VLC from the Start menu.** Start VLC from the Start menu, then double-click `Episode 2.mkv`.
   See: a second VLC window opens, plays it and has the 16 videos; the first VLC's playlist stays empty. Close both.
3. **"Allow only one instance" on.** Start VLC, tick it, Save, close VLC. Start VLC from the Start menu, then double-click `Episode 2.mkv`.
   See: no second window; it plays in that VLC with the 16 videos. Close VLC.
4. **Enqueue on.** Start VLC, tick "Allow only one instance" and then "Enqueue items into playlist in one instance mode" (it can only be ticked while "Allow only one instance" is), Save, close VLC. Double-click `Episode 2.mkv`.
   See: VLC starts, plays it, 16 videos. Open Messages. Then double-click `Season 2\Episode 1.mkv`.
   See: it's added at the end and doesn't play; Episode 2.mkv keeps playing; no new `folder` line. Wait 15 s, then double-click that item in the playlist.
   See: it plays; nothing else changes. Messages: `item ... started, no build: added ... s before it started`. Close VLC.
5. **File manager off.** Start VLC, untick "Enqueue items ..." first (unticking "Allow only one instance" only greys it out), then "Allow only one instance" and "Use only one instance when started from file manager", Save, close VLC. Double-click `Episode 1.mkv`, then `Season 2\Episode 1.mkv`.
   See: two VLC windows, the first with the 16 videos, the second with Season 2's 2. Close both.
6. **Back to the noted values.** Start VLC, set the three boxes back (the defaults: tick only "Use only one instance when started from file manager"), Save, close VLC. Then:
   ```powershell
   Select-String -Path "$env:APPDATA\vlc\vlcrc" -Pattern '^#?(extraintf|one-instance|one-instance-when-started-from-file|playlist-enqueue)='
   ```
   See: `extraintf=luaintf{intf=autofolder}` (saving the preferences kept it), and with the defaults `#one-instance=0`, `#one-instance-when-started-from-file=1`, `#playlist-enqueue=0`.
7. **Main interfaces boxes.** Start VLC, Tools → Preferences, Show settings: All, Interface → Main interfaces. Tick "Web", untick it again, Save, close VLC. Run the command from step 6 again.
   See: `extraintf=lua` (the page replaced autofolder's entry). Start VLC from the Start menu.
   See: a Terminal window opens too (VLC's command-line interface; seen 2026-11-14). Close VLC, wait 5 s, then:
   ```powershell
   Get-Process vlc -ErrorAction SilentlyContinue
   ```
   See: nothing (if it lists a VLC, write that down and end it with `Stop-Process -Name vlc`). Double-click `install.cmd`.
   See: `vlcrc: removed "lua" from extraintf (VLC's preferences page writes it in place of autofolder's entry; ...)`, then `vlcrc: added luaintf{intf=autofolder} to extraintf`. The command from step 6 shows `extraintf=luaintf{intf=autofolder}` again. Double-click `Episode 1.mkv`: the 16 videos, and no console window. Close VLC.

## 11. Uninstall and install again
1. Close VLC. Double-click `uninstall.cmd` in the project folder.
   See: `Removed 4 files from ...`, `Removed the settings file ...autofolder.ini` (only if there is one), `Backed up vlcrc to ...`, `vlcrc: removed luaintf{intf=autofolder} from extraintf`, then `Uninstalled.` in green.
2. vlcrc differs from the backup the uninstall made only in the extraintf line:
   ```powershell
   $baks = @(Get-ChildItem "$env:APPDATA\vlc\vlcrc.autofolder-*.bak" | Sort-Object Name); Compare-Object (Get-Content $baks[-1].FullName) (Get-Content "$env:APPDATA\vlc\vlcrc")
   ```
   See: two lines, `extraintf=luaintf{intf=autofolder}` with `<=` and `#extraintf=` with `=>` (or, if extraintf had other entries, that line without the autofolder entry).
3. Double-click `Episode 1.mkv`. See: only Episode 1.mkv in the playlist; the View menu has no "Auto Folder Playlist settings". Close VLC.
4. Double-click `install.cmd`. See: `Copied 4 files ...`, `Backed up vlcrc to ...`, `vlcrc: added luaintf{intf=autofolder} to extraintf`, `Installed.`
5. vlcrc is byte for byte what it was before the uninstall (the uninstall's backup, the second newest):
   ```powershell
   $baks = @(Get-ChildItem "$env:APPDATA\vlc\vlcrc.autofolder-*.bak" | Sort-Object Name); (Get-FileHash "$env:APPDATA\vlc\vlcrc").Hash -eq (Get-FileHash $baks[-2].FullName).Hash
   ```
   See: `True`.
6. Double-click `Episode 1.mkv`. See: the 16 videos. Close VLC.
7. The `vlcrc.autofolder-*.bak` files in `%APPDATA%\vlc` can be deleted now, or kept.

## Runs
Full runs on the installed VLC. A difference from "See" is listed with its step, and what was fixed.
- 2026-11-13 (To do 5): the whole list once, over several sessions; the details are in [archive/05-readme-manual-test.md](archive/05-readme-manual-test.md).
- 2026-11-14, before the public release. Code changed since the last run: install.ps1 only (To do 8). Step 10.7 passed earlier that day (To do 8). The installed Lua files were the repo's (same hashes). The one-instance settings at the start: "Allow only one instance" off, "Use only one instance when started from file manager" off (the user's choice from the last run), "Enqueue ..." off.
  - 0: 0.1, 0.2 (`build-big` passed; the media folder matched 0.3's list, `.dot-hidden.mkv` and `attribute-hidden.mkv` included, and `big\` held 500 files), 0.5 (no settings file) and 0.6 (`3.0.24` three times) checked by Claude. 0.3 and 0.4 passed (the user).
  - 1: 1.1 passed (an update: no change to vlcrc, no new backup; Claude checked after: `extraintf=luaintf{intf=autofolder}`, the 4 files as in the repo). 1.2 skipped (first install only).
  - 2: passed (the user).
  - 3 to 9 and 10.1 to 10.6: not run again. The user stopped the manual run after section 2 (decisions.md, 2026-11-14). The Lua code is the same as in the 2026-11-13 run, which passed them.
  - The automated tests: 23 cases, 0 failures, 100.7 s (measured).
  - 11, by Claude from a script, VLC closed: 11.1, 11.2, 11.4 and 11.5 passed; after the reinstall vlcrc was byte for byte what it was before. 11.1 printed no `Removed the settings file` line because there was no settings file: its "See:" now says "only if there is one". 11.3 not run. In place of 11.6: the installed VLC with no window (`--intf dummy`, the real vlcrc) on `Episode 1.mkv` logged `started`, the default settings and `16 videos, 2 before and 13 after Episode 1.mkv; added 15`, with no `lua error` line; it changed nothing in `%APPDATA%\vlc`.
