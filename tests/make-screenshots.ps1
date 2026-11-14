<#
.SYNOPSIS
    Makes the README pictures, docs\images\playlist.png and docs\images\settings.png, with
    the portable test VLC (tools\vlc) and a demo folder. By hand only; not a run-tests case.

.DESCRIPTION
    1. Makes the demo folder %TEMP%\vlc-autofolder-demo\Course: 10 videos "Lecture 1 -
       Introduction.mkv" to "Lecture 10 - Review.mkv", each a 2-minute solid-colour
       YUV4MPEG2 video, one day apart (so date and name order agree).
    2. Refills the portable folder with the current Lua files (as run-tests does) and writes
       its Qt settings, so VLC starts with the docked playlist in the List view.
    3. Starts the portable VLC with Lecture 4 (with --no-video: a playing video would replace
       the playlist), waits for the build and the lengths, and captures the window.
    4. Brings VLC to the front, opens View > Auto Folder Playlist settings with the keys
       Alt+I, Up, Up, Enter (VLC's Qt has no UI Automation), moves the dialog next to the
       main window, widens it, and captures it.
    The installed VLC and %APPDATA%\vlc are never used. A VLC window shows for ~15 s; don't
    click or type meanwhile: the keys go to the window in front. It stops before sending
    keys if VLC isn't in front. Check playlist.png afterwards: VLC 3.0's window sometimes
    shows a build's moves late (research/vlc-lua-api.md, "Playlist"); run it again then.
    How it works: research/vlc-lua-api.md, "Screenshots of the Qt window".

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tests\make-screenshots.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'A console report for the person running it.')]
[CmdletBinding()]
param(
    [string]$OutDir,
    [int]$Width = 760,         # the main window, in logical pixels
    [int]$Height = 470,
    [int]$DialogWidth = 600    # wide enough for the whole default video-type list
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestCommon.ps1')
if (-not $OutDir) { $OutDir = Join-Path $root 'docs\images' }

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class ShotWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int size);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
}
"@
# Per-monitor DPI aware, so window and frame rectangles are in the same pixels on every screen
# (the dialog may open on another screen with another scale).
if (-not [ShotWin]::SetProcessDpiAwarenessContext([IntPtr](-4))) { [void][ShotWin]::SetProcessDPIAware() }

$topmost = [IntPtr](-1)

function Get-FrameRect([IntPtr]$Handle) {
    # The visible window frame, without the invisible resize borders.
    $f = New-Object ShotWin+RECT
    [void][ShotWin]::DwmGetWindowAttribute($Handle, 9, [ref]$f, 16)  # DWMWA_EXTENDED_FRAME_BOUNDS
    $f
}

function Save-WindowImage([IntPtr]$Handle, [string]$Path) {
    # PrintWindow (PW_RENDERFULLCONTENT): the window draws itself, so nothing on top of it shows.
    $r = New-Object ShotWin+RECT; [void][ShotWin]::GetWindowRect($Handle, [ref]$r)
    $f = Get-FrameRect $Handle
    $bmp = New-Object Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc(); [void][ShotWin]::PrintWindow($Handle, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
    $crop = New-Object Drawing.Rectangle ($f.L - $r.L), ($f.T - $r.T), ($f.R - $f.L), ($f.B - $f.T)
    $crop = [Drawing.Rectangle]::Intersect($crop, (New-Object Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height))
    $out = $bmp.Clone($crop, $bmp.PixelFormat)
    $out.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose(); $out.Dispose()
    Write-Host ('{0} ({1} x {2})' -f $Path, $crop.Width, $crop.Height)
}

function Get-YuvVideo([int[]]$Rgb) {
    # 160x90, 1 frame/s, 120 frames of one colour (full-range BT.601, as C420jpeg means).
    $r, $g, $b = $Rgb
    $y = [byte][Math]::Round(0.299 * $r + 0.587 * $g + 0.114 * $b)
    $u = [byte][Math]::Round(128 - 0.168736 * $r - 0.331264 * $g + 0.5 * $b)
    $v = [byte][Math]::Round(128 + 0.5 * $r - 0.418688 * $g - 0.081312 * $b)
    $w = 160; $h = 90; $luma = $w * $h; $quarter = $luma / 4
    $frame = New-Object byte[] ($luma * 3 / 2)
    for ($i = 0; $i -lt $luma; $i++) { $frame[$i] = $y }
    for ($i = 0; $i -lt $quarter; $i++) { $frame[$luma + $i] = $u; $frame[$luma + $quarter + $i] = $v }
    $stream = New-Object IO.MemoryStream
    $header = [Text.Encoding]::ASCII.GetBytes("YUV4MPEG2 W$w H$h F1:1 Ip A1:1 C420jpeg`n")
    $stream.Write($header, 0, $header.Length)
    $frameHeader = [Text.Encoding]::ASCII.GetBytes("FRAME`n")
    for ($n = 0; $n -lt 120; $n++) {
        $stream.Write($frameHeader, 0, $frameHeader.Length)
        $stream.Write($frame, 0, $frame.Length)
    }
    , $stream.ToArray()
}

function Get-VlcWindow([int]$ProcessId) {
    # The visible top-level windows of the process: Handle, Title, Class.
    $found = New-Object Collections.Generic.List[object]
    $callback = [ShotWin+EnumProc]{
        param($handle)  # the second argument (lParam) is unused
        $owner = 0; [void][ShotWin]::GetWindowThreadProcessId($handle, [ref]$owner)
        if ($owner -eq $ProcessId -and [ShotWin]::IsWindowVisible($handle)) {
            $title = New-Object Text.StringBuilder 256; [void][ShotWin]::GetWindowText($handle, $title, 256)
            $class = New-Object Text.StringBuilder 256; [void][ShotWin]::GetClassName($handle, $class, 256)
            $found.Add([pscustomobject]@{ Handle = $handle; Title = "$title"; Class = "$class" })
        }
        $true
    }
    [void][ShotWin]::EnumWindows($callback, [IntPtr]::Zero)
    $found
}

function Invoke-Foreground([IntPtr]$Handle) {
    # A background process can't simply take the foreground: attach to the input of the window
    # in front and press Alt first; minimize and restore as a last try. True when it worked.
    $me = [ShotWin]::GetCurrentThreadId()
    for ($try = 1; $try -le 8 -and [ShotWin]::GetForegroundWindow() -ne $Handle; $try++) {
        $frontPid = 0
        $frontThread = [ShotWin]::GetWindowThreadProcessId([ShotWin]::GetForegroundWindow(), [ref]$frontPid)
        [void][ShotWin]::AttachThreadInput($me, $frontThread, $true)
        [ShotWin]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [ShotWin]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
        [void][ShotWin]::SetForegroundWindow($Handle); [void][ShotWin]::BringWindowToTop($Handle)
        [void][ShotWin]::AttachThreadInput($me, $frontThread, $false)
        Start-Sleep -Milliseconds 250
        if ($try -ge 4 -and [ShotWin]::GetForegroundWindow() -ne $Handle) {
            [void][ShotWin]::ShowWindow($Handle, 6); Start-Sleep -Milliseconds 300   # minimize
            [void][ShotWin]::ShowWindow($Handle, 9); Start-Sleep -Milliseconds 400   # restore
        }
    }
    [ShotWin]::GetForegroundWindow() -eq $Handle
}

Assert-TestVlc
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# 1. The demo folder.
$demo = Join-Path ([IO.Path]::GetTempPath()) 'vlc-autofolder-demo\Course'
if (Test-Path -LiteralPath $demo) { Remove-Item -LiteralPath $demo -Recurse -Force }
New-Item -ItemType Directory -Force -Path $demo | Out-Null
$lectures = 'Introduction', 'Variables', 'Conditions', 'Loops', 'Functions',
            'Lists', 'Dictionaries', 'Files', 'Debugging', 'Review'
$colours = @(@(52, 101, 164), @(78, 154, 6), @(196, 160, 0), @(206, 92, 0), @(117, 80, 123),
             @(32, 128, 128), @(164, 0, 0), @(85, 87, 83), @(52, 101, 164), @(78, 154, 6))
$time = New-Object DateTime 2026, 9, 1, 10, 0, 0
for ($k = 0; $k -lt $lectures.Count; $k++) {
    $path = Join-Path $demo ('Lecture {0} - {1}.mkv' -f ($k + 1), $lectures[$k])
    [IO.File]::WriteAllBytes($path, (Get-YuvVideo $colours[$k]))
    [IO.File]::SetLastWriteTime($path, $time.AddDays($k))
}

# 2. Fresh portable folder; its Qt settings live in portable\vlc\ (measured 2026-11-14).
Initialize-PortableLua
$qtDir = Join-Path $portable 'vlc'
New-Item -ItemType Directory -Force -Path $qtDir | Out-Null
[IO.File]::WriteAllText((Join-Path $qtDir 'vlc-qt-interface.ini'),
    "[MainWindow]`r`nplaylist-visible=true`r`npl-dock-status=true`r`n[Playlist]`r`nview-mode=2`r`n")

# 3. The playlist.
$vlcArgs = @('--no-one-instance', '--no-crashdump', '--no-qt-privacy-ask', '--no-qt-updates-notif',
    '--no-qt-video-autoresize', '--no-media-library', '--no-video', '--extraintf', 'luaintf{intf=autofolder}',
    ('"{0}"' -f (Join-Path $demo 'Lecture 4 - Loops.mkv')))
$vlc = Start-Process -FilePath $vlcExe -ArgumentList $vlcArgs -PassThru
try {
    for ($i = 0; $i -lt 150 -and $vlc.MainWindowTitle -notlike 'Lecture 4*'; $i++) {
        Start-Sleep -Milliseconds 100; $vlc.Refresh()
    }
    if ($vlc.MainWindowTitle -notlike 'Lecture 4*') { throw 'VLC did not start playing Lecture 4 within 15 s.' }
    $main = $vlc.MainWindowHandle
    $scale = [ShotWin]::GetDpiForWindow($main) / 96
    [void][ShotWin]::SetWindowPos($main, $topmost, 80, 80, [int]($Width * $scale), [int]($Height * $scale), 0x10)
    Start-Sleep -Seconds 5   # the build (next 300 ms poll) and VLC reading the 10 lengths
    Save-WindowImage $main (Join-Path $OutDir 'playlist.png')

    # 4. The settings dialog: View (Alt+I), its last entries are the extensions, ours before VLsub.
    # A menu shows as another visible window of VLC (a popup); try up to 3 times to open it.
    $menu = $null
    for ($try = 1; $try -le 3 -and -not $menu; $try++) {
        if (-not (Invoke-Foreground $main)) { throw 'VLC is not the window in front; no keys sent. Run it again.' }
        [Windows.Forms.SendKeys]::SendWait('{ESC}'); Start-Sleep -Milliseconds 200   # no menu half-open
        [Windows.Forms.SendKeys]::SendWait('%i')
        for ($i = 0; $i -lt 15 -and -not $menu; $i++) {
            Start-Sleep -Milliseconds 100
            $menu = Get-VlcWindow $vlc.Id | Where-Object { $_.Handle -ne $main } | Select-Object -First 1
        }
    }
    if (-not $menu) { throw 'The View menu did not open (3 tries).' }
    if ([ShotWin]::GetForegroundWindow() -ne $main) { throw 'VLC is no longer the window in front; stopped.' }
    [Windows.Forms.SendKeys]::SendWait('{UP}'); Start-Sleep -Milliseconds 250
    [Windows.Forms.SendKeys]::SendWait('{UP}'); Start-Sleep -Milliseconds 250
    [Windows.Forms.SendKeys]::SendWait('{ENTER}')
    $dialog = $null
    for ($i = 0; $i -lt 80 -and -not $dialog; $i++) {
        Start-Sleep -Milliseconds 100
        $dialog = (Get-VlcWindow $vlc.Id | Where-Object { $_.Title -eq 'Auto Folder Playlist' } | Select-Object -First 1).Handle
    }
    if (-not $dialog) {
        $open = (Get-VlcWindow $vlc.Id | ForEach-Object { '"{0}" ({1})' -f $_.Title, $_.Class }) -join ', '
        throw "The settings dialog did not open within 8 s. VLC's windows: $open"
    }
    $f = Get-FrameRect $main
    [void][ShotWin]::SetWindowPos($dialog, $topmost, $f.L + [int](120 * $scale), $f.T + [int](110 * $scale), 0, 0, 0x11)
    Start-Sleep -Milliseconds 700
    $d = New-Object ShotWin+RECT; [void][ShotWin]::GetWindowRect($dialog, [ref]$d)
    [void][ShotWin]::SetWindowPos($dialog, $topmost, 0, 0, [int]($DialogWidth * $scale), ($d.B - $d.T), 0x12)
    Start-Sleep -Milliseconds 700
    Save-WindowImage $dialog (Join-Path $OutDir 'settings.png')
}
finally {
    if (-not $vlc.HasExited) { Stop-Process -Id $vlc.Id; [void]$vlc.WaitForExit(5000) }
    Remove-Item -LiteralPath (Split-Path -Parent $demo) -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'Done. Check playlist.png: Lecture 1 to 10 in order, Lecture 4 in bold.'
