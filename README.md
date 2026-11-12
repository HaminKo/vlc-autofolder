# vlc-autofolder

Open one video in VLC and the rest of its folder is added to the playlist automatically, so Next and Previous just work.

When you open a single video file in VLC 3.0 on Windows (for example by double-clicking it in File Explorer), a small Lua script that runs in the background adds every other video in the same folder to the playlist. It keeps them in your chosen sort order (date modified or natural name order), with the opened file in its correct place. The file you opened keeps playing. You don't have to open the folder or click anything.

## Status
In development. Built for VLC 3.0.24 on Windows 11. What works so far:
- Opening a video (double-click, Open File, or dropping it on the window) adds the other videos of its folder, before and after it, in the sort order you chose (date modified, oldest first, unless you change it). The folder goes at the end of the playlist, after items you added yourself, which keep their order.
- The sort order and the video file types are set in a dialog (View menu) or a small settings file (see below); a new sort order re-sorts the playlist within about two seconds, without restarting VLC.
- Opening a video from another folder replaces the previous folder's videos with the new folder's; your own items stay.
- Opening a video of the same folder again leaves one copy of each file, adds new files, and removes items whose file was deleted.
- Clicking an item, Next and Previous never change the playlist. Neither does opening several files at once or an .m3u playlist.
- Large folders and network paths (`\\server\share\...`) work. In tests, a folder of 500 videos was in place within about half a second, and the file didn't start later. Network paths were tested through a share on the same PC; a real network share and mapped drives are still to be checked by hand.
- Install and uninstall with a double-click (see Install below).

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
- `extensions`: without the line, or with it empty, the default list: mp4 mkv avi mov wmv webm m4v flv ts mpg mpeg m2ts mts 3gp ogv vob. Other files in the folder are ignored.
- While VLC runs, a change is picked up within about two seconds (the file is read every second, and a change counts once two reads agree, so a half-saved file is never used). A new sort order re-sorts the folder in the playlist at once; the playing file keeps playing. New video types apply the next time you open a file.
- A wrong value is ignored (that setting keeps its default) and shows as a warning in Tools → Messages, e.g. `autofolder.ini line 1: unknown sort order "newest"`.

## Troubleshooting
- **Nothing is added after the install:** VLC loads the script only when it starts, so close every VLC window and start it again. Tools → Messages (verbosity 2) should then show `[autofolder] started`; if it doesn't, close VLC and run the install again.
- **It stopped working after a change in VLC's preferences:** in Tools → Preferences → All → Interface → Main interfaces, ticking or unticking a box there may rewrite the "Extra interface modules" text and drop `{intf=autofolder}`. Close VLC and run the install again.
- **See what the script did:** Tools → Messages, verbosity 2 (debug). Its lines start with `[autofolder]`. After each build, one line gives the number of videos and how long it took, e.g. `folder D:\Shows\: 24 videos, 4 before and 19 after Episode 05.mkv; added 23, removed 0; 4 moves; 3 ms (scan 2 ms)`.
- **Settings not applied:** at start, and after each change of the settings file, one line shows the settings in use and where it looked for the file, e.g. `settings: sort name-az; video types mp4 mkv avi (from C:\Users\you\AppData\Roaming\vlc\autofolder.ini)`, or `(defaults: no file ...)` when it found none. Check the file name: Notepad may have saved it as `autofolder.ini.txt`.
- **No "Auto Folder Playlist settings" in the View menu:** `autofolder_dialog.lua` must be in `%APPDATA%\vlc\lua\extensions\`; then restart VLC. A script VLC couldn't load shows in Tools → Messages as `Error loading script ...autofolder_dialog.lua`.
- **The menu entry opens nothing:** `autofolder_settings.lua` must be in `%APPDATA%\vlc\lua\modules\`. Tools → Messages then shows `module 'autofolder_settings' not found`.
- **"cannot read the folder":** the folder couldn't be listed, for example a network share that was briefly offline. The script doesn't retry: open the file again.

## Limitations
- On a network share, VLC reads each added file's details (such as its length) in the background. That's slower than on a local disk (about 12 files per second through a test share on the same PC, against 500 files in 4 s locally). Playback isn't affected, but the lengths appear in the playlist gradually.
- VLC 3.0 itself can't play files opened as `\\localhost\...`. Use the computer's name or a drive letter instead.
- When you remove a type from `extensions`, files of that type already in the playlist stay there until you open a video from another folder.
- VLC 3.0's playlist window doesn't show items a script moves. So when folder videos have to change places (a new sort order, or a video of the folder opened again), the script removes those videos from the playlist and adds them again in their new place; the others stay. VLC then reads their lengths again, which is quick on a local disk and gradual on a network share. The playing video and items from other folders are never removed this way.

## Install
1. Close VLC (every window).
2. Double-click `install.cmd` in this folder. A window shows what it did; press any key to close it.
   It copies the Lua scripts to `%APPDATA%\vlc\lua\` and adds `luaintf{intf=autofolder}` to the "Extra interface modules" setting (`extraintf`) in VLC's settings file, `%APPDATA%\vlc\vlcrc`. Other entries in that setting stay. Before changing vlcrc it saves a copy next to it, e.g. `vlcrc.autofolder-20261112-153000.bak`. Only the `extraintf` line changes (it is added at the end if vlcrc has none).
3. Start VLC and open any video.

- **"VLC's settings file isn't there yet":** VLC writes vlcrc the first time it starts. Start VLC, click Continue on its first-start question, close it, and run the install again.
- **Update:** get the new files and run the install again. It replaces the scripts; vlcrc and your settings stay as they are.
- **In PowerShell instead:** `powershell -ExecutionPolicy Bypass -File .\install.ps1` (and `.\uninstall.ps1`) in this folder does the same; the `.cmd` files only start these scripts.
- **Uninstall:** close VLC and double-click `uninstall.cmd`. It removes the scripts, your Auto Folder settings (`autofolder.ini`) and only its own entry from vlcrc (after saving another copy). Other VLC settings you changed since the install are kept. The `.bak` copies stay; delete them when you no longer need them.

## Development
The tests run the real VLC 3.0.24 (a portable copy, so your own VLC settings are never touched) with no window. In Windows PowerShell, in this folder:
```powershell
powershell -ExecutionPolicy Bypass -File .\tests\setup-tools.ps1   # once: downloads the test VLC and luacheck into tools\
powershell -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

## Credits
- [VLC media player](https://www.videolan.org/vlc/) and its Lua scripting interface, by VideoLAN and the VLC authors (GPL-2.0-or-later).
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) by Microsoft (MIT): a development check only.
- [luacheck](https://github.com/lunarmodules/luacheck) by Peter Melnichenko and the Lunar Modules team (MIT): a development check only, downloaded by `tests\setup-tools.ps1`.
