# vlc-autofolder

Open one video in VLC and the rest of its folder is added to the playlist automatically, so Next and Previous just work.

When you open a single video file in VLC 3.0 on Windows (for example by double-clicking it in File Explorer), a small Lua script that runs in the background adds every other video in the same folder to the playlist. It keeps them in your chosen sort order (date modified or natural name order), with the opened file in its correct place. The file you opened keeps playing. You don't have to open the folder or click anything.

## Status
In development: nothing works yet. Built for VLC 3.0.24 on Windows 11.

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
