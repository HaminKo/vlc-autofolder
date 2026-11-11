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

# Paths ($root, $vlcExe, $media, $testRoot, $userVlc, ...) and the shared helpers.
. (Join-Path $PSScriptRoot 'TestCommon.ps1')

# Each case starts one VLC.
#   Driver:       a script in tests\lua\intf (without .lua).
#   Autofolder:   also load lua\intf\autofolder.lua (chain syntax).
#   Files:        put on VLC's command line, like a double-click; relative to the media folder,
#                 or a full path.
#   LogMustMatch: regexes that must each match a line of VLC's log.
#   Config:       more fields for the driver's config table, in Lua syntax (e.g. "open=[[a.mkv]]").
# The driver's config table (lua-config) holds: out (its results file), media (the media
# folder), videos (the video list file, oldest first) and unc (the media folder as a UNC path).
$cases = @(
    @{
        Name = 'smoke'; Driver = 'test_smoke'; Autofolder = $true; Files = @('Episode 2.mkv'); TimeoutSec = 20
        LogMustMatch = @('\[autofolder\] started', 'autofolder\.lua:\d+: Interrupted\.$')
    }
    @{
        # Every video plus one UNC path, so the playlist holds the URIs VLC makes itself.
        Name = 'api'; Driver = 'test_api'; Files = $testVideos + @(Join-Path $uncMedia 'Episode 1.mkv'); TimeoutSec = 30
    }
    @{
        Name = 'move'; Driver = 'test_move'; Files = @('episode 3.MP4'); TimeoutSec = 40
    }
    @{
        # The helper module autofolder_core; no file to play.
        Name = 'core'; Driver = 'test_core'; Files = @(); TimeoutSec = 20
    }
    # Building the folder from the first, a middle and the last video by date (16 videos, the
    # dot-name not counted), and from the dot-named one, which the scan itself skips. The move
    # counts are the fewest moves to the front for each case.
    @{
        Name = 'build-first'; Driver = 'test_build'; Autofolder = $true; Files = @('Episode 10.mkv'); TimeoutSec = 30
        LogMustMatch = @('\[autofolder\] folder .+: 16 videos; added 0 before and 15 after Episode 10\.mkv; 0 moves$')
    }
    @{
        # The Japanese name: Unicode in the opened file and in the files added around it.
        Name = 'build-middle'; Driver = 'test_build'; Autofolder = $true; Files = @($testVideos[12]); TimeoutSec = 30
        LogMustMatch = @('\[autofolder\] folder .+: 16 videos; added 12 before and 3 after .+; 12 moves$')
    }
    @{
        Name = 'build-last'; Driver = 'test_build'; Autofolder = $true; Files = @('attribute-hidden.mkv'); TimeoutSec = 30
        LogMustMatch = @('\[autofolder\] folder .+: 16 videos; added 15 before and 0 after attribute-hidden\.mkv; 15 moves$')
    }
    @{
        Name = 'build-dot'; Driver = 'test_build'; Autofolder = $true; Files = @('.dot-hidden.mkv'); TimeoutSec = 30
        LogMustMatch = @('\[autofolder\] folder .+: 17 videos; added 15 before and 1 after \.dot-hidden\.mkv; 15 moves$')
    }
    @{
        # A running VLC: the user's own item (a video in another folder) is in the playlist, then a
        # folder file is opened. The user's item stays first; it and 2 videos are moved.
        Name = 'build-user'; Driver = 'test_build'; Autofolder = $true; Files = @(); TimeoutSec = 30
        Config = 'user=[[{0}]],open=[[Episode 1.mkv]]' -f (Join-Path $testRoot 'summer.mkv')
        LogMustMatch = @('\[autofolder\] folder .+: 16 videos; added 2 before and 13 after Episode 1\.mkv; 3 moves$')
    }
)

function Invoke-TestCase {
    # Runs one case; writes its report and returns $true when it passed.
    param([hashtable]$Spec)
    $out = Join-Path $testRoot "results\$($Spec.Name).txt"
    $log = Join-Path $testRoot "logs\$($Spec.Name).log"
    $intf = "luaintf{intf=$($Spec.Driver)}"
    if ($Spec.Autofolder) { $intf = "luaintf{intf=autofolder}:$intf" }
    $extra = if ($Spec.Config) { ',' + $Spec.Config } else { '' }
    $luaConfig = '{0}={{out=[[{1}]],media=[[{2}]],videos=[[{3}]],unc=[[{4}]]{5}}}' -f $Spec.Driver, $out, $media, $videoList, $uncMedia, $extra
    $vlcArgs = (Get-HeadlessVlcArgumentList -Log $log) + @(
        '--no-one-instance', '--no-one-instance-when-started-from-file'   # never hand files to another VLC
        '--extraintf', "`"$intf`""
        "--lua-config=`"$luaConfig`""
    )
    foreach ($file in $Spec.Files) {
        if (-not [IO.Path]::IsPathRooted($file)) { $file = Join-Path $media $file }
        $vlcArgs += '"' + $file + '"'
    }

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
    # A Lua error in any script, except the "Interrupted." that ends a script when VLC closes:
    # autofolder's, and the driver's in testlib's quit loop (a driver interrupted before it
    # finished has no "done" line, which fails above).
    foreach ($line in $logLines) {
        if ($line -like 'lua error:*' -and $line -notmatch '(autofolder|testlib)\.lua:\d+: Interrupted\.$') {
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
Assert-TestVlc
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
Initialize-PortableLua
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
