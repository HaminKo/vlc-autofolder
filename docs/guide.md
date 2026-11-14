# vlc-autofolder guide

The details behind the [README](../README.md): what works, the settings file, VLC's one-instance settings, troubleshooting, limitations and what the install changes.

## What works
In development. Built for VLC 3.0.24 on Windows 11. What works so far:
- Opening a video (double-click, Open File, or dropping it on the video picture) adds the other videos of its folder, before and after it, in the sort order you chose (date modified, oldest first, unless you change it). The folder goes at the end of the playlist, after items you added yourself, which keep their order.
- The sort order and the video file types are set in a dialog (View menu) or a small settings file (see below); a new sort order re-sorts the playlist within about two seconds, without restarting VLC.
- Opening a video from another folder replaces the previous folder's videos with the new folder's; your own items stay.
- Opening a video of the same folder again leaves one copy of each file, adds new files, and removes items whose file was deleted.
- Clicking an item, Next and Previous don't change the playlist (unless that item was only just added at the end: see Limitations). Neither does opening an .m3u playlist of several files, or several files at once in one VLC (for example dropped together onto its window). Selecting several files in Explorer and pressing Enter is different: Windows opens them one by one. With VLC's default settings they all go to one VLC, which plays the one it got last and gets that file's whole folder (each file once). With "Use only one instance when started from file manager" off, each file gets its own VLC with its folder (see "When VLC is already open"). To play just the selected files, drop them together onto VLC's window.
- Large folders, network paths (`\\server\share\...`) and mapped network drives work. In tests, a folder of 500 videos was in place within about half a second, and the file didn't start later. Network paths and mapped drives were tested through a share on the same PC, not on a real network share.
- Install and uninstall with a double-click (see [Install](../README.md#install)).

## Sort order and video types
In VLC, choose **View → Auto Folder Playlist settings**. The dialog has the sort order and the video file types (separated by spaces; leave the field empty for the default list). **Save** applies them within about two seconds, without restarting VLC; **Cancel** (or closing the window) changes nothing. A wrong value in the settings file shows as a note in the dialog.

The dialog saves to `autofolder.ini` in VLC's user folder (`%APPDATA%\vlc\autofolder.ini`). Without the file, the defaults apply. You can also edit it in Notepad (for example with the Skins interface, which has no View menu), but the dialog's Save rewrites the whole file, so comments you typed there are lost. An example:
```ini
# sort: date-oldest, date-newest, name-az or name-za
sort=name-az
# the file types that count as video, separated by spaces
extensions=mp4 mkv avi
```
- `sort`: `date-oldest` (date modified, oldest first; the default), `date-newest`, `name-az` or `name-za`. Names sort naturally: Episode 2 before Episode 10. Files with the same date go by name, A to Z.
- `extensions`: without the line, or with it empty, the default list: mp4 mkv avi mov wmv webm m4v flv ts mpg mpeg m2ts mts 3gp ogv vob. Other files in the folder are ignored, and so are subfolders and names that start with a dot.
- While VLC runs, a change is picked up within about two seconds (the file is read every second, and a change counts once two reads agree, so a half-saved file is never used). A new sort order re-sorts the folder in the playlist at once; the playing file keeps playing. New video types apply the next time you open a file.
- A wrong value is ignored and shows as a warning, e.g. `autofolder.ini line 1: unknown sort order "newest" (one of: date-oldest, date-newest, name-az, name-za); using date-oldest`. An unknown sort order keeps the default; a word in `extensions` that isn't a file type is left out (with no valid word left, the default list applies). Tools → Messages shows the warning when you change the file while VLC runs; for a file that was already wrong when VLC started, see the note in the dialog or the log file (Troubleshooting).

## When VLC is already open
What happens to a video you double-click while VLC is open depends on three settings in Tools → Preferences → Interface, under "Playlist and Instances": "Allow only one instance" (off by default), "Use only one instance when started from file manager" (on) and "Enqueue items into playlist in one instance mode" (off). autofolder builds a folder only for a file that is added at the end of the playlist and starts playing within 10 seconds, as an opened file does.

| Settings | You double-click a video while VLC is open | autofolder |
|---|---|---|
| Defaults, and that VLC was started by a double-click | That VLC adds the file at the end and plays it | Builds the file's folder, in place of the previous folder |
| Defaults, and that VLC was started from the Start menu | A second VLC opens and plays the file | The second VLC builds the folder; the first one is unchanged |
| "Allow only one instance" on | The open VLC adds the file at the end and plays it, however it was started | Builds the file's folder |
| "Use only one instance when started from file manager" off (and "Allow only one instance" off) | Every double-click opens a new VLC | Each VLC builds its own folder |
| "Allow only one instance" and "Enqueue items into playlist in one instance mode" on (Enqueue can only be ticked together with the other) | The open VLC adds the file at the end and keeps playing what it played | Nothing; but if the file starts within 10 seconds (you click it, or the video before it ends), its folder is built |

- With no VLC open, a double-click starts VLC, which plays the file and builds its folder, whatever these settings say.
- Explorer's right-click entries (in Windows 11 under "Show more options"): "Play with VLC media player" works like a double-click, "Add to VLC media player's Playlist" like enqueue mode.

## Troubleshooting
- **A double-click opens another player:** a double-click only reaches VLC when VLC is the default app for that file type. In Windows 11: Settings → Apps → Default apps, search for the type (e.g. `.mkv`) and pick VLC media player. Or right-click the file → Open with → VLC media player, which does the same as a double-click.
- **A dropped file isn't followed by its folder:** a file dropped onto the playlist list is only added there; VLC doesn't play it, so for autofolder it wasn't opened. Drop it on the video picture, or use Media → Open File.
- **Each double-click opens another VLC window:** a VLC opened from the Start menu or a shortcut doesn't receive double-clicked files (see "When VLC is already open"). Close it and double-click the file, or turn on "Allow only one instance". If even then every double-click opens a new VLC, VLC's own files may be of mixed versions after an update. This PowerShell command should print the same version three times:
  ```powershell
  foreach ($f in 'vlc.exe', 'libvlc.dll', 'libvlccore.dll') { '{0}: {1}' -f $f, (Get-Item "$env:ProgramFiles\VideoLAN\VLC\$f").VersionInfo.FileVersion }
  ```
  If it doesn't, reinstall VLC (if the installer offers to delete preferences and cache, leave that unticked: it would also remove autofolder).
- **Nothing is added after the install:** VLC loads the script only when it starts, so close every VLC window and start it again. To check that it runs, open Tools → Messages (see below) and then a video with Media → Open File: a line starting `[autofolder]` should appear. If none does, close VLC and run the install again.
- **It stopped working after a change in VLC's preferences:** in Tools → Preferences → All → Interface → Main interfaces, ticking or unticking a box there may rewrite the "Extra interface modules" text and drop `{intf=autofolder}`. Close VLC and run the install again.
- **See what the script did:** Tools → Messages, Verbosity 2 (debug), and `autofolder` in its Filter box. The script's lines start with `[autofolder]`. The window shows only what happens after you open it, so open it first, then do what you want to check; lines from VLC's start (such as `[autofolder] started`, or the folder built for the file VLC was started with) are only in a log file (next entry). After each build, one line gives the number of videos and how long it took, e.g. `folder D:\Shows\: 24 videos, 4 before and 19 after Episode 05.mkv; added 23, re-added 0, removed 0; 4 moves; 3 ms (scan 2 ms)`. A line `lua error: ... autofolder.lua ... Interrupted.` each time VLC closes is expected: that's how VLC stops the script.
- **Everything from VLC's start, in a file:** close VLC, start it from PowerShell with a log file, do what you want to check, close VLC, then show autofolder's lines:
  ```powershell
  & "$env:ProgramFiles\VideoLAN\VLC\vlc.exe" --verbose=2 --file-logging --logfile="$env:TEMP\vlc-log.txt"
  ```
  ```powershell
  Select-String -Path "$env:TEMP\vlc-log.txt" -Pattern 'autofolder'
  ```
- **Settings not applied:** at start, and after each change of the settings file, one line shows the settings in use and where it looked for the file, e.g. `settings: sort name-az; video types mp4 mkv avi (from C:\Users\you\AppData\Roaming\vlc\autofolder.ini)`, or `(defaults: no file ...)` when it found none. Check the file name: Notepad may have saved it as `autofolder.ini.txt`.
- **No "Auto Folder Playlist settings" in the View menu:** `autofolder_dialog.lua` must be in `%APPDATA%\vlc\lua\extensions\`; then restart VLC. A script VLC couldn't load shows in the log file (VLC loads it at start) as `Error loading script ...autofolder_dialog.lua`.
- **The menu entry opens nothing, or nothing is added at all:** autofolder needs `autofolder_settings.lua` in `%APPDATA%\vlc\lua\modules\`; close VLC and run the install again. Without it, VLC logs `module 'autofolder_settings' not found`, at VLC's start (only in the log file) and when you open the dialog (in Tools → Messages).
- **"cannot read the folder":** the folder couldn't be listed, for example a network share that was briefly offline. The script doesn't retry: open the file again.

## Limitations
- On a network share, VLC reads each added file's details (such as its length) in the background. That's slower than on a local disk (about 12 files per second through a test share on the same PC, against 500 files in 4 s locally). Playback isn't affected, but the lengths appear in the playlist gradually.
- VLC 3.0 itself can't play files opened as `\\localhost\...`. Use the computer's name or a drive letter instead.
- When you remove a type from `extensions`, files of that type already in the playlist stay there until you open a video from another folder.
- autofolder can't see how an item came into the playlist, only when it was added and when it started. So a file that starts less than 10 seconds after it was added at the end of the playlist counts as opened and builds its folder, even if you only queued it (for example with "Add to VLC media player's Playlist" in the last seconds of the video before it).
- VLC 3.0's playlist window doesn't show items a script moves. So when folder videos have to change places (a new sort order, or a video of the folder opened again), the script removes those videos from the playlist and adds them again in their new place; the others stay. VLC then reads their lengths again, which is quick on a local disk and gradual on a network share. The playing video and items from other folders are never removed this way.

## Install details
The install copies the Lua scripts to `%APPDATA%\vlc\lua\` and adds `luaintf{intf=autofolder}` to the "Extra interface modules" setting (`extraintf`) in VLC's settings file, `%APPDATA%\vlc\vlcrc`. Other entries in that setting stay. Before changing vlcrc it saves a copy next to it, e.g. `vlcrc.autofolder-20261112-153000.bak`. Only the `extraintf` line changes (it is added at the end if vlcrc has none).

- **In PowerShell instead:** `powershell -ExecutionPolicy Bypass -File .\install.ps1` (and `.\uninstall.ps1`) in the project folder does the same; the `.cmd` files only start these scripts.
