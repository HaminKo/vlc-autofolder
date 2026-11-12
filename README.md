# vlc-autofolder

Open one video in VLC and the rest of its folder is added to the playlist automatically, so Next and Previous just work.

When you open a single video file in VLC 3.0 on Windows (for example by double-clicking it in File Explorer), a small Lua script that runs in the background adds every other video in the same folder to the playlist. It keeps them in your chosen sort order (date modified or natural name order), with the opened file in its correct place. The file you opened keeps playing. You don't have to open the folder or click anything.

## Status
In development. Built for VLC 3.0.24 on Windows 11. What works so far:
- Opening a video (double-click, Open File, or dropping it on the window) adds the other videos of its folder, before and after it, in the sort order you chose (date modified, oldest first, unless you change it). Items you added to the playlist yourself keep their places.
- The sort order and the video file types are set in a small settings file (see below); a new sort order re-sorts the playlist within about two seconds, without restarting VLC.
- Opening a video from another folder replaces the previous folder's videos with the new folder's; your own items stay.
- Opening a video of the same folder again leaves one copy of each file, adds new files, and removes items whose file was deleted.
- Clicking an item, Next and Previous never change the playlist. Neither does opening several files at once or an .m3u playlist.
- Large folders and network paths (`\\server\share\...`) work. In tests, a folder of 500 videos was in place within about half a second, and the file didn't start later. Network paths were tested through a share on the same PC; a real network share and mapped drives are still to be checked by hand.

The install script and a View-menu dialog for the settings are still to come.

## Sort order and video types
The settings are in `autofolder.ini` in VLC's user folder (`%APPDATA%\vlc\autofolder.ini`). Without the file, the defaults apply. To change them, create or edit it in Notepad, for example:
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
- **See what the script did:** Tools → Messages, verbosity 2 (debug). Its lines start with `[autofolder]`. After each build, one line gives the number of videos and how long it took, e.g. `folder D:\Shows\: 24 videos, 4 before and 19 after Episode 05.mkv; added 23, removed 0; 4 moves; 3 ms (scan 2 ms)`.
- **Settings not applied:** at start, and after each change of the settings file, one line shows the settings in use and where it looked for the file, e.g. `settings: sort name-az; video types mp4 mkv avi (from C:\Users\you\AppData\Roaming\vlc\autofolder.ini)`, or `(defaults: no file ...)` when it found none. Check the file name: Notepad may have saved it as `autofolder.ini.txt`.
- **"cannot read the folder":** the folder couldn't be listed, for example a network share that was briefly offline. The script doesn't retry: open the file again.

## Limitations
- On a network share, VLC reads each added file's details (such as its length) in the background. That's slower than on a local disk (about 12 files per second through a test share on the same PC, against 500 files in 4 s locally). Playback isn't affected, but the lengths appear in the playlist gradually.
- VLC 3.0 itself can't play files opened as `\\localhost\...`. Use the computer's name or a drive letter instead.
- When you remove a type from `extensions`, files of that type already in the playlist stay there until you open a video from another folder.
- VLC 3.0's playlist window doesn't show items a script moves. So a new sort order removes the folder's videos from the playlist and adds them again in the new order. VLC then reads their lengths again, which is quick on a local disk and gradual on a network share. A folder video you added to the playlist yourself is moved instead, so the window may still show it in its old place. VLC plays it in the right order either way.

## Install (planned)
1. Close VLC.
2. In PowerShell, in this folder, run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```
   It copies the Lua scripts to `%APPDATA%\vlc\lua\`, backs up VLC's settings file (`vlcrc`), and enables the script as an extra interface.
3. Start VLC and open any video.

To remove it, run `.\uninstall.ps1` the same way.

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
