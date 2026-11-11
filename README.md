# vlc-autofolder

Open one video in VLC and the rest of its folder is added to the playlist automatically, so Next and Previous just work.

When you open a single video file in VLC 3.0 on Windows (for example by double-clicking it in File Explorer), a small Lua script that runs in the background adds every other video in the same folder to the playlist. It keeps them in your chosen sort order (date modified or natural name order), with the opened file in its correct place. The file you opened keeps playing. You don't have to open the folder or click anything.

## Status
In development. Built for VLC 3.0.24 on Windows 11. What works so far:
- Opening a video (double-click, Open File, or dropping it on the window) adds the other videos of its folder, before and after it, by date modified. Items you added to the playlist yourself keep their places.
- Opening a video from another folder replaces the previous folder's videos with the new folder's; your own items stay.
- Opening a video of the same folder again leaves one copy of each file, adds new files, and removes items whose file was deleted.
- Clicking an item, Next and Previous never change the playlist. Neither does opening several files at once or an .m3u playlist.
- Large folders and network paths (`\\server\share\...`) work. In tests, a folder of 500 videos was in place within about half a second, and the file didn't start later. Network paths were tested through a share on the same PC; a real network share and mapped drives are still to be checked by hand.

The install script and the sort switch are still to come.

## Troubleshooting
- **See what the script did:** Tools → Messages, verbosity 2 (debug). Its lines start with `[autofolder]`. After each build, one line gives the number of videos and how long it took, e.g. `folder D:\Shows\: 24 videos, 4 before and 19 after Episode 05.mkv; added 23, removed 0; 4 moves; 3 ms (scan 2 ms)`.
- **"cannot read the folder":** the folder couldn't be listed, for example a network share that was briefly offline. The script doesn't retry: open the file again.

## Limitations
- On a network share, VLC reads each added file's details (such as its length) in the background. That's slower than on a local disk (about 12 files per second through a test share on the same PC, against 500 files in 4 s locally). Playback isn't affected, but the lengths appear in the playlist gradually.
- VLC 3.0 itself can't play files opened as `\\localhost\...`. Use the computer's name or a drive letter instead.

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
