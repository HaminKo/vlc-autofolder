@echo off
rem Double-click to install vlc-autofolder into VLC (close VLC first); uninstall.cmd calls it
rem with -Uninstall. Runs install.ps1 next to this file, passing the arguments on, and keeps
rem the window open to show the result. All the logic is in install.ps1.
setlocal
if exist "%~dp0install.ps1" goto run
rem Started inside Explorer's zip view: Windows extracted only this file.
echo install.ps1 isn't next to this file. If you opened the zip, extract it first
echo (right-click it, Extract All), then run this again from the extracted folder.
set code=1
goto done
:run
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set code=%errorlevel%
:done
pause
exit /b %code%
