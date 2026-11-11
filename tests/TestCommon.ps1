<#
.SYNOPSIS
    Shared by the test scripts (run-tests.ps1, spike-one-instance.ps1). Dot-source it:
        . (Join-Path $PSScriptRoot 'TestCommon.ps1')

.DESCRIPTION
    Sets the paths below in the caller's scope and defines helpers for the portable test
    VLC (tools\vlc), the test media folder and the check that the real %APPDATA%\vlc stays
    unchanged.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Some paths are only used by the scripts that dot-source this file.')]
param()

$root = Split-Path -Parent $PSScriptRoot
$vlcExe = Join-Path $root 'tools\vlc\vlc.exe'
# With this folder next to vlc.exe, VLC keeps its settings and Lua user folder there,
# not in %APPDATA%\vlc. It must exist before VLC starts.
$portable = Join-Path $root 'tools\vlc\portable'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) 'vlc-autofolder-tests'
$media = Join-Path $testRoot 'media'
# The media folder as a UNC path through the admin share, e.g. \\localhost\C$\Users\...\media.
$uncMedia = '\\localhost\{0}${1}' -f $media.Substring(0, 1), $media.Substring(2)
# Written by Initialize-TestFolder: the video names, oldest first, one per line (UTF-8).
$videoList = Join-Path $testRoot 'videos.txt'
# VLC finds %APPDATA% through the shell API, not the environment variable.
$userVlc = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'vlc'

# The test videos in the media folder, oldest first: the date order is deliberately not the
# name order. The names cover sorting, URI encoding and Unicode. This file is kept ASCII
# (PowerShell 5.1 reads a .ps1 without BOM as ANSI), so non-ASCII names use char codes.
$testVideos = @(
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
    ('caf{0}.mkv' -f [char]0x00E9)                                # cafe with e-acute
    ((-join [char[]]@(0x65E5, 0x672C, 0x8A9E)) + '.mkv')          # "Japanese" in Japanese
    ([char]::ConvertFromUtf32(0x1F3AC) + ' clip.mp4')             # clapper-board emoji
    'double  space.mov'
    '.dot-hidden.mkv'
    'attribute-hidden.mkv'
)

function Assert-TestVlc {
    # Throws unless the test VLC exists and no copy of it is running.
    if (-not (Test-Path -LiteralPath $vlcExe)) {
        throw "No test VLC at $vlcExe. Run: powershell -ExecutionPolicy Bypass -File tests\setup-tools.ps1"
    }
    if (Get-TestVlcProcess) { throw "A test VLC ($vlcExe) is still running. Close it or end it in Task Manager." }
}

function Get-TestVlcProcess {
    Get-Process vlc -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $vlcExe }
}

function Get-HeadlessVlcArgumentList {
    # VLC arguments for a run with no window and a debug log file. Callers add the
    # one-instance options themselves.
    param([string]$Log)
    @(
        '-I', 'dummy', '--dummy-quiet'      # no window, no console
        # Without this, a crashing VLC writes a dump into the real %APPDATA%\vlc\crashdump
        # (the portable folder doesn't apply), and the next VLC start asks to send it.
        '--no-crashdump'
        '--no-media-library'                # don't write ml.xspf
        # Don't load Episode 1.srt with Episode 1.mkv: with no video output to show it on,
        # VLC took ~6 s to stop that file when asked to play another (measured 2026-11-11).
        '--no-sub-autodetect-file'
        '--vout', 'dummy', '--aout', 'dummy'
        '--verbose=2', '--file-logging', "--logfile=`"$Log`""
    )
}

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
    # The test folder: $testVideos (1 hour apart, from 2026-01-01 12:00 local time), the
    # files below, a subfolder, empty results\ and logs\ folders, and $videoList.
    # Not videos: must be ignored. Name and content.
    $others = [ordered]@{
        'Episode 1.srt' = "1`n00:00:00,000 --> 00:00:05,000`nsubtitle`n"
        'cover.jpg'     = "not a picture`n"
        'notes.txt'     = "notes`n"
        'info.nfo'      = "info`n"
        'playlist.m3u'  = "#EXTM3U`nEpisode 1.mkv`nEpisode 2.mkv`n"
    }

    $season2 = Join-Path $media 'Season 2'
    $refresh = Join-Path $testRoot 'refresh'
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
    foreach ($dir in @($media, $season2, $refresh, (Join-Path $testRoot 'results'), (Join-Path $testRoot 'logs'))) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $video = Get-Y4mVideo
    $utf8 = New-Object Text.UTF8Encoding($false)
    $time = New-Object DateTime 2026, 1, 1, 12, 0, 0  # local time, whole seconds
    foreach ($name in $testVideos) {
        $path = Join-Path $media $name
        [IO.File]::WriteAllBytes($path, $video)
        [IO.File]::SetLastWriteTime($path, $time)
        $time = $time.AddHours(1)
    }
    [IO.File]::WriteAllText($videoList, (($testVideos -join "`n") + "`n"), $utf8)
    $hidden = Join-Path $media 'attribute-hidden.mkv'
    [IO.File]::SetAttributes($hidden, [IO.File]::GetAttributes($hidden) -bor [IO.FileAttributes]::Hidden)
    foreach ($name in $others.Keys) {
        $path = Join-Path $media $name
        [IO.File]::WriteAllText($path, $others[$name], $utf8)
        [IO.File]::SetLastWriteTime($path, $time)
    }
    # In a subfolder: ignored when the media folder is built; the folder switch case builds it.
    # The refresh case deletes and adds files in refresh\ while VLC runs.
    $folders = [ordered]@{
        $season2 = @('Episode 1.mkv', 'Episode 2.mkv'), (New-Object DateTime 2026, 2, 1, 12, 0, 0)
        $refresh = @('a.mkv', 'b.mkv', 'c.mkv'), (New-Object DateTime 2026, 3, 1, 12, 0, 0)
    }
    foreach ($dir in $folders.Keys) {
        $names, $time = $folders[$dir]
        foreach ($name in $names) {
            $path = Join-Path $dir $name
            [IO.File]::WriteAllBytes($path, $video)
            [IO.File]::SetLastWriteTime($path, $time)
            $time = $time.AddHours(1)
        }
    }
    # Outside the media folder: a file dated in summer time (DST), to check the times stat reports.
    $summer = Join-Path $testRoot 'summer.mkv'
    [IO.File]::WriteAllBytes($summer, $video)
    [IO.File]::SetLastWriteTime($summer, (New-Object DateTime 2026, 7, 1, 12, 0, 0))
}

function Initialize-PortableLua {
    # A fresh portable folder with the current Lua files: lua\ and tests\lua\ merged into
    # tools\vlc\portable\lua\.
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
}

function Get-FolderSnapshot {
    param([string]$Path)
    # Always at least one line, so Compare-Object never gets an empty list.
    if (-not (Test-Path -LiteralPath $Path)) { return '(missing)' }
    '(exists)'
    Get-ChildItem -LiteralPath $Path -Recurse -Force |
        ForEach-Object { '{0}|{1}|{2:o}' -f $_.FullName, $_.Length, $_.LastWriteTimeUtc }
}
