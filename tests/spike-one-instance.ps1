<#
.SYNOPSIS
    One-time spike (To do 1 step B): what VLC 3.0.24 does when a second VLC is started with
    a file while one is already running, in the one-instance settings that matter.

.DESCRIPTION
    Not a run-tests.ps1 case: a second VLC in one-instance mode hands its file to ANY running
    VLC 3.0.24 (the user's own included), so this refuses to run while any VLC is open, and
    stops if one is opened meanwhile. While it runs (~35 s, estimated), a file opened with VLC
    may go to the hidden test VLC. If it stops early (Ctrl+C or an error), it closes the test
    VLCs it started.

    For each case, with the portable test VLC (tools\vlc) and default settings otherwise:
      1. Starts a first VLC with Episode 10.mkv and tests\lua\intf\spike_one_instance.lua,
         which records that VLC's playlist whenever it changes.
      2. Once it plays, starts a second VLC with Episode 2.mkv.
      3. Reports whether the second VLC handed its file over (it exits at once) or ran on its
         own (still running after 5 s; then it is closed), and the first VLC's playlist with
         the time of each change ("*" marks the playing item). After a hand-over it waits up
         to 12 s for the first VLC to play the new file.
    It also prints the commands Explorer runs for VLC's .mkv file type (from the registry).
    Results files and logs: %TEMP%\vlc-autofolder-tests\results\spike-*.txt and logs\.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tests\spike-one-instance.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'A console report for the person running it.')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'TestCommon.ps1')

# The first VLC's file: one without a .srt next to it (see --no-sub-autodetect-file in
# TestCommon.ps1 for why that matters).
$firstFile = 'Episode 10.mkv'

function Get-ExplorerCommand {
    # The command line Explorer runs for a verb of VLC's .mkv file type, or $null.
    param([string]$Verb)
    $key = "Registry::HKEY_CLASSES_ROOT\VLC.mkv\shell\$Verb\command"
    if (-not (Test-Path -LiteralPath $key)) { return $null }
    (Get-ItemProperty -LiteralPath $key).'(default)'
}

function Get-ExplorerOption {
    # The options of a verb's command: "C:\...\vlc.exe" --started-from-file "%1" gives
    # --started-from-file. Falls back to $Default when the verb isn't registered.
    param([string]$Verb, [string[]]$Default)
    $command = Get-ExplorerCommand $Verb
    if ($command -match '^"[^"]+"\s+(.*?)\s*"%1"\s*$') { return @(-split $Matches[1] | Where-Object { $_ }) }
    $Default
}

function Assert-NoOtherVlc {
    # Any running VLC 3.0.24 can receive the second VLC's file, so none may run besides ours.
    if (Get-Process vlc -ErrorAction SilentlyContinue | Where-Object { $_.Path -ne $vlcExe }) {
        throw 'Another VLC is open: the spike stops so it never sends that VLC a test file. Close every VLC (also in the notification area) and run it again.'
    }
}

function Read-SharedLine {
    # Reads a text file that VLC may still hold open for writing.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)
    try { @($reader.ReadToEnd() -split "`n" | Where-Object { $_ }) }
    finally { $reader.Dispose() }
}

function Invoke-SpikeCase {
    param([hashtable]$Spec)
    $out = Join-Path $testRoot "results\spike-$($Spec.Name).txt"
    $logFirst = Join-Path $testRoot "logs\spike-$($Spec.Name)-first.log"
    $logSecond = Join-Path $testRoot "logs\spike-$($Spec.Name)-second.log"
    $luaConfig = 'spike_one_instance={{out=[[{0}]]}}' -f $out
    $argsFirst = (Get-HeadlessVlcArgumentList -Log $logFirst) + @(
        '--extraintf', '"luaintf{intf=spike_one_instance}"', "--lua-config=`"$luaConfig`""
    ) + $Spec.First + @('"' + (Join-Path $media $firstFile) + '"')
    $argsSecond = (Get-HeadlessVlcArgumentList -Log $logSecond) + $Spec.Second +
        @('"' + (Join-Path $media 'Episode 2.mkv') + '"')

    Write-Host ''
    Write-Host "$($Spec.Name): $($Spec.Note)" -ForegroundColor Cyan
    Write-Host "  first VLC:  $($Spec.First -join ' ') $firstFile"
    Write-Host "  second VLC: $($Spec.Second -join ' ') Episode 2.mkv"

    $problems = New-Object Collections.Generic.List[string]
    $first = $null
    $second = $null
    try {
        $first = Start-Process -FilePath $vlcExe -ArgumentList $argsFirst -PassThru -WindowStyle Hidden
        $null = $first.Handle  # keeps the handle, so ExitCode is readable after exit (PowerShell 5.1)
        $deadline = (Get-Date).AddSeconds(15)
        while (-not ((Read-SharedLine $out) -contains 'info ready') -and (Get-Date) -lt $deadline -and -not $first.HasExited) {
            Start-Sleep -Milliseconds 100
        }
        if ((Read-SharedLine $out) -contains 'info ready') {
            Assert-NoOtherVlc
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $second = Start-Process -FilePath $vlcExe -ArgumentList $argsSecond -PassThru -WindowStyle Hidden
            $null = $second.Handle
            if ($second.WaitForExit(5000)) {
                Write-Host ('  second VLC: handed its file over and exited after {0:N1} s (exit code {1})' -f $watch.Elapsed.TotalSeconds, $second.ExitCode)
                # Give the first VLC up to 12 s to switch to the new file: 1.5 s and 4 s were
                # sometimes too short in this headless setup (measured). Times are in the playlist lines.
                $deadline = (Get-Date).AddSeconds(12)
                while ((Get-Date) -lt $deadline -and -not ((Read-SharedLine $out) -match '\*Episode 2\.mkv')) {
                    Start-Sleep -Milliseconds 200
                }
            }
            else {
                Write-Host '  second VLC: ran on its own (still running after 5 s; closed now)'
            }
        }
        else {
            $problems.Add('the first VLC never reported "ready"')
        }
        [IO.File]::WriteAllText("$out.stop", '')
        if (-not $first.WaitForExit(10000)) {
            $problems.Add('the first VLC did not exit within 10 s and was killed')
        }
    }
    finally {
        # Never leave a hidden test VLC behind: it could receive the user's files later.
        foreach ($process in @($second, $first)) {
            if ($process -and -not $process.HasExited) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                $process.WaitForExit()
            }
        }
    }

    $lines = Read-SharedLine $out
    foreach ($line in $lines) {
        if ($line -like 'info playlist *') { Write-Host "  playlist: $($line.Substring(14))" }
        elseif ($line -like 'fail *') { $problems.Add($line) }
    }
    if ($lines -notcontains 'done') { $problems.Add('the driver did not finish (no "done" line)') }
    foreach ($log in @($logFirst, $logSecond)) {
        foreach ($line in (Read-SharedLine $log) -match 'one instance') {
            Write-Host "  log ($(Split-Path -Leaf $log)): $($line.Trim())"
        }
    }
    foreach ($problem in $problems) { Write-Host "  ! $problem" -ForegroundColor Red }
    $problems.Count -eq 0
}

# Preconditions: no VLC at all, or the second VLC could hand its file to it.
Assert-TestVlc
Assert-NoOtherVlc

Write-Host 'Explorer, .mkv:'
$userChoice = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.mkv\UserChoice' -ErrorAction SilentlyContinue).ProgId
Write-Host "  default app (UserChoice ProgId): $userChoice"
foreach ($verb in @('Open', 'AddToPlaylistVLC', 'PlayWithVLC')) {
    Write-Host "  VLC.mkv $verb`: $(Get-ExplorerCommand $verb)"
}

# @() keeps a one-option result a list (a function returns a one-item list as the item).
$open = @(Get-ExplorerOption 'Open' @('--started-from-file'))
$add = @(Get-ExplorerOption 'AddToPlaylistVLC' @('--started-from-file', '--playlist-enqueue'))
$cases = @(
    @{ Name = 'explorer-open'; First = $open; Second = $open
        Note = 'VLC is the default app: a double-click starts VLC, a second double-click follows' }
    @{ Name = 'explorer-add'; First = $open; Second = $add
        Note = 'a double-click, then "Add to VLC media player''s Playlist" (= the enqueue setting on)' }
    @{ Name = 'started-plainly'; First = @(); Second = $open
        Note = 'VLC started without --started-from-file (Start menu, then File > Open), then a double-click' }
    @{ Name = 'one-instance'; First = @('--one-instance'); Second = @('--one-instance')
        Note = '"Allow only one instance" on; files given on the command line' }
    @{ Name = 'from-file-off'; First = $open + @('--no-one-instance-when-started-from-file')
        Second = $open + @('--no-one-instance-when-started-from-file')
        Note = '"Use only one instance when started from file manager" off' }
)

$userVlcBefore = Get-FolderSnapshot $userVlc
Initialize-PortableLua
Initialize-TestFolder

$failed = 0
foreach ($spec in $cases) {
    Assert-NoOtherVlc
    if (-not (Invoke-SpikeCase $spec)) { $failed++ }
    if (Get-TestVlcProcess) { throw 'A test VLC is still running after the case.' }
}

Write-Host ''
if (Compare-Object @($userVlcBefore) @(Get-FolderSnapshot $userVlc)) {
    Write-Host "FAIL $userVlc changed during the spike" -ForegroundColor Red
    $failed++
}
else {
    Write-Host "PASS $userVlc unchanged" -ForegroundColor Green
}
if ($failed) { exit 1 }
