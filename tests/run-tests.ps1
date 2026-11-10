<#
.SYNOPSIS
    Runs the tests in the portable test VLC (tools\vlc) with no window.

.DESCRIPTION
    - Copies lua\ (the add-on) and tests\lua\ (the test drivers) into tools\vlc\portable\lua\.
    - Builds the test media in %TEMP%\vlc-autofolder-tests\media.
    - Runs each case in $cases: one headless VLC with a driver script (tests\lua\intf\test_*.lua),
      usually next to autofolder. The driver writes ok/fail lines to a results file
      (format: tests\lua\intf\modules\testlib.lua).
    - Fails if anything in the real %APPDATA%\vlc changed.
    Needs the tools from tests\setup-tools.ps1. Exit code 0 when every case passes.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1 -Case smoke
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'A console test runner: colored PASS/FAIL lines for the person running it.')]
[CmdletBinding()]
param(
    # Run only these cases (names from $cases below).
    [string[]]$Case
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$vlcExe = Join-Path $root 'tools\vlc\vlc.exe'
# With this folder next to vlc.exe, VLC keeps its settings and Lua user folder there,
# not in %APPDATA%\vlc. It must exist before VLC starts.
$portable = Join-Path $root 'tools\vlc\portable'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) 'vlc-autofolder-tests'
$media = Join-Path $testRoot 'media'
# VLC finds %APPDATA% through the shell API, not the environment variable.
$userVlc = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'vlc'

# Each case starts one VLC.
#   Driver:       a script in tests\lua\intf (without .lua).
#   Autofolder:   also load lua\intf\autofolder.lua (chain syntax).
#   Files:        put on VLC's command line, like a double-click; relative to the media folder.
#   LogMustMatch: regexes that must each match a line of VLC's log.
$cases = @(
    @{
        Name = 'smoke'; Driver = 'test_smoke'; Autofolder = $true; Files = @('Episode 2.mkv'); TimeoutSec = 20
        LogMustMatch = @('\[autofolder\] started', 'autofolder\.lua:\d+: Interrupted\.$')
    }
)

function Get-Y4mVideo {
    # A 2-minute, 32x32, 1 frame/s raw video (YUV4MPEG2). VLC plays it whatever the file
    # extension (its avcodec demuxer detects the format), so it serves as .mkv, .mp4, ...
    $w = 32; $h = 32; $frames = 120
    $stream = New-Object IO.MemoryStream
    $header = [Text.Encoding]::ASCII.GetBytes("YUV4MPEG2 W$w H$h F1:1 Ip A1:1 C420jpeg`n")
    $stream.Write($header, 0, $header.Length)
    $frameHeader = [Text.Encoding]::ASCII.GetBytes("FRAME`n")
    $frame = New-Object byte[] ($w * $h * 3 / 2)
    for ($i = $w * $h; $i -lt $frame.Length; $i++) { $frame[$i] = 128 }  # grey chroma
    for ($n = 0; $n -lt $frames; $n++) {
        for ($i = 0; $i -lt $w * $h; $i++) { $frame[$i] = [byte](($n * 2) % 256) }  # brightness ramp
        $stream.Write($frameHeader, 0, $frameHeader.Length)
        $stream.Write($frame, 0, $frame.Length)
    }
    , $stream.ToArray()
}

function Initialize-TestFolder {
    # The test folder. The names cover sorting, URI encoding and Unicode. The script is kept
    # ASCII (PowerShell 5.1 reads a .ps1 without BOM as ANSI), so non-ASCII names use char codes.
    $eAcute = [string][char]0x00E9
    $japanese = -join [char[]]@(0x65E5, 0x672C, 0x8A9E)
    $clapper = [char]::ConvertFromUtf32(0x1F3AC)
    # Videos, oldest first: the date order is deliberately not the name order.
    $videos = @(
        'Episode 10.mkv'
        'Episode 2.mkv'
        'Episode 1.mkv'
        'episode 3.MP4'
        'hash # sign.mkv'
        'percent 100% and %20 literal.mkv'
        'a & b.mkv'
        '[Group] Title [1080p].mkv'
        "it's here.mp4"
        'comma, here.avi'
        'plus+equals=semi;colon.webm'
        "caf$eAcute.mkv"
        "$japanese.mkv"
        "$clapper clip.mp4"
        'double  space.mov'
        '.dot-hidden.mkv'
        'attribute-hidden.mkv'
    )
    # Not videos: must be ignored. Name and content.
    $others = [ordered]@{
        'Episode 1.srt' = "1`n00:00:00,000 --> 00:00:05,000`nsubtitle`n"
        'cover.jpg'     = "not a picture`n"
        'notes.txt'     = "notes`n"
        'info.nfo'      = "info`n"
        'playlist.m3u'  = "#EXTM3U`nEpisode 1.mkv`nEpisode 2.mkv`n"
    }

    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
    foreach ($dir in @($media, (Join-Path $media 'Season 2'), (Join-Path $testRoot 'results'), (Join-Path $testRoot 'logs'))) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $video = Get-Y4mVideo
    $utf8 = New-Object Text.UTF8Encoding($false)
    $time = New-Object DateTime 2026, 1, 1, 12, 0, 0  # local time, whole seconds
    foreach ($name in $videos) {
        $path = Join-Path $media $name
        [IO.File]::WriteAllBytes($path, $video)
        [IO.File]::SetLastWriteTime($path, $time)
        $time = $time.AddHours(1)
    }
    $hidden = Join-Path $media 'attribute-hidden.mkv'
    [IO.File]::SetAttributes($hidden, [IO.File]::GetAttributes($hidden) -bor [IO.FileAttributes]::Hidden)
    foreach ($name in $others.Keys) {
        $path = Join-Path $media $name
        [IO.File]::WriteAllText($path, $others[$name], $utf8)
        [IO.File]::SetLastWriteTime($path, $time)
    }
    [IO.File]::WriteAllBytes((Join-Path $media 'Season 2\Episode 1.mkv'), $video)  # in a subfolder: must be ignored
}

function Get-FolderSnapshot {
    param([string]$Path)
    # Always at least one line, so Compare-Object never gets an empty list.
    if (-not (Test-Path -LiteralPath $Path)) { return '(missing)' }
    '(exists)'
    Get-ChildItem -LiteralPath $Path -Recurse -Force |
        ForEach-Object { '{0}|{1}|{2:o}' -f $_.FullName, $_.Length, $_.LastWriteTimeUtc }
}

function Get-TestVlcProcess {
    Get-Process vlc -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $vlcExe }
}

function Invoke-TestCase {
    # Runs one case; writes its report and returns $true when it passed.
    param([hashtable]$Spec)
    $out = Join-Path $testRoot "results\$($Spec.Name).txt"
    $log = Join-Path $testRoot "logs\$($Spec.Name).log"
    $intf = "luaintf{intf=$($Spec.Driver)}"
    if ($Spec.Autofolder) { $intf = "luaintf{intf=autofolder}:$intf" }
    $luaConfig = '{0}={{out=[[{1}]],media=[[{2}]]}}' -f $Spec.Driver, $out, $media
    $vlcArgs = @(
        '-I', 'dummy', '--dummy-quiet'                                    # no window, no console
        '--no-one-instance', '--no-one-instance-when-started-from-file'   # never hand files to another VLC
        '--no-media-library'                                              # don't write ml.xspf
        '--vout', 'dummy', '--aout', 'dummy'
        '--verbose=2', '--file-logging', "--logfile=`"$log`""
        '--extraintf', "`"$intf`""
        "--lua-config=`"$luaConfig`""
    )
    foreach ($file in $Spec.Files) { $vlcArgs += '"' + (Join-Path $media $file) + '"' }

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $vlcExe -ArgumentList $vlcArgs -PassThru -WindowStyle Hidden
    $null = $process.Handle  # keeps the handle, so ExitCode is readable after exit (PowerShell 5.1)
    $timedOut = -not $process.WaitForExit($Spec.TimeoutSec * 1000)
    if ($timedOut) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
    }
    $watch.Stop()

    $problems = New-Object Collections.Generic.List[string]
    $lines = @()
    if (Test-Path -LiteralPath $out) { $lines = [IO.File]::ReadAllLines($out, [Text.Encoding]::UTF8) }
    $logLines = @()
    if (Test-Path -LiteralPath $log) { $logLines = [IO.File]::ReadAllLines($log, [Text.Encoding]::UTF8) }

    if ($timedOut) { $problems.Add("VLC did not exit within $($Spec.TimeoutSec) s and was killed") }
    elseif ($process.ExitCode -ne 0) { $problems.Add("VLC exit code $($process.ExitCode)") }
    if ($lines -notcontains 'done') { $problems.Add('the driver did not finish (no "done" line)') }
    foreach ($line in $lines) { if ($line -like 'fail *') { $problems.Add($line) } }
    # A Lua error in any script, except the "Interrupted." that ends autofolder when VLC closes.
    # (Drivers quit VLC themselves, so they are never interrupted in a passing case.)
    foreach ($line in $logLines) {
        if ($line -like 'lua error:*' -and $line -notmatch 'autofolder\.lua:\d+: Interrupted\.$') {
            $problems.Add("log: $line")
        }
    }
    foreach ($pattern in $Spec.LogMustMatch) {
        if (-not ($logLines -match $pattern)) { $problems.Add("log: no line matches /$pattern/") }
    }

    $passed = $problems.Count -eq 0
    $status = if ($passed) { 'PASS' } else { 'FAIL' }
    $color = if ($passed) { 'Green' } else { 'Red' }
    Write-Host ('{0} {1} ({2:N1} s)' -f $status, $Spec.Name, $watch.Elapsed.TotalSeconds) -ForegroundColor $color
    foreach ($line in $lines) { if ($line -ne 'done') { Write-Host "    $line" } }
    if (-not $passed) {
        foreach ($problem in $problems) { Write-Host "  ! $problem" -ForegroundColor Red }
        Write-Host "  VLC log: $log"
    }
    $passed
}

# Preconditions
if (-not (Test-Path -LiteralPath $vlcExe)) {
    throw "No test VLC at $vlcExe. Run: powershell -ExecutionPolicy Bypass -File tests\setup-tools.ps1"
}
if (Get-TestVlcProcess) { throw "A test VLC ($vlcExe) is still running. Close it or end it in Task Manager." }
$ownVlcOpen = [bool](Get-Process vlc -ErrorAction SilentlyContinue | Where-Object { $_.Path -ne $vlcExe })
if ($ownVlcOpen) {
    Write-Host "Note: your own VLC is open. The tests don't touch it, but if it saves its settings meanwhile, the $userVlc check fails." -ForegroundColor Yellow
}
$selected = $cases
if ($Case) {
    $selected = @($cases | Where-Object { $Case -contains $_.Name })
    $unknown = @($Case | Where-Object { ($cases.Name) -notcontains $_ })
    if ($unknown) { throw "Unknown case(s): $($unknown -join ', '). Cases: $(($cases.Name) -join ', ')" }
}

$total = [Diagnostics.Stopwatch]::StartNew()
$userVlcBefore = Get-FolderSnapshot $userVlc

# Fresh portable folder with the current Lua files: lua\ and tests\lua\ merged.
if (Test-Path -LiteralPath $portable) { Remove-Item -LiteralPath $portable -Recurse -Force }
$portableLua = Join-Path $portable 'lua'
New-Item -ItemType Directory -Force -Path $portableLua | Out-Null
foreach ($source in @((Join-Path $root 'lua'), (Join-Path $root 'tests\lua'))) {
    $prefix = (Get-Item -LiteralPath $source).FullName.TrimEnd('\') + '\'
    Get-ChildItem -LiteralPath $source -Recurse -File | ForEach-Object {
        if (-not $_.FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unexpected path $($_.FullName) outside $prefix"
        }
        $relative = $_.FullName.Substring($prefix.Length)
        $target = Join-Path $portableLua $relative
        if (Test-Path -LiteralPath $target) { throw "lua\ and tests\lua\ both have $relative" }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $target
    }
}
Initialize-TestFolder

$failed = 0
foreach ($spec in $selected) {
    if (-not (Invoke-TestCase $spec)) { $failed++ }
}

if (Get-TestVlcProcess) { Write-Host 'FAIL a test VLC is still running after the tests' -ForegroundColor Red; $failed++ }
$userVlcAfter = Get-FolderSnapshot $userVlc
if (Compare-Object @($userVlcBefore) @($userVlcAfter)) {
    $hint = if ($ownVlcOpen) { ' (your own VLC was open: probably it, not the tests)' } else { '' }
    Write-Host "FAIL $userVlc changed during the tests$hint" -ForegroundColor Red
    $failed++
}
else {
    Write-Host "PASS $userVlc unchanged" -ForegroundColor Green
}

Write-Host ('{0} case(s), {1} failure(s), {2:N1} s' -f $selected.Count, $failed, $total.Elapsed.TotalSeconds)
if ($failed) { exit 1 }
