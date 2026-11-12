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
#   LogMustNotMatch: regexes that no line of VLC's log may match.
#   Config:       more fields for the driver's config table, in Lua syntax (e.g. "open=[[a.mkv]]").
#   Big:          needs the 500-video folder ($bigFolder), made only when such a case runs.
#   Unc:          needs $uncMedia (the admin share C$); skipped, not failed, when it can't be reached.
#   Settings:     the text of the settings file (autofolder.ini in the test VLC's user folder,
#                 tools\vlc\portable) at the start; without it, there is no settings file.
# The driver's config table (lua-config) holds: out (its results file), media (the media
# folder), videos (the video list file, oldest first) and unc (the media folder as a UNC path).
$cases = @(
    @{
        Name = 'smoke'; Driver = 'test_smoke'; Autofolder = $true; Files = @('Episode 2.mkv'); TimeoutSec = 20
        LogMustMatch = @(
            '\[autofolder\] started'
            '\[autofolder\] settings: sort date-oldest; video types mp4 mkv .+ \(defaults: no file .+\\portable\\autofolder\.ini\)$'
            'autofolder\.lua:\d+: Interrupted\.$'
        )
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
    # The settings file (test_settings.lua describes each scenario).
    @{
        Name = 'settings-parse'; Driver = 'test_settings'; Files = @(); TimeoutSec = 20
        Config = 'scenario=[[parse]]'
    }
    @{
        Name = 'settings-live'; Driver = 'test_settings'; Autofolder = $true; Files = @('Episode 2.mkv'); TimeoutSec = 40
        Config = 'scenario=[[live]]'; Settings = "sort=name-za`n"
        LogMustMatch = @(
            '\[autofolder\] settings: sort name-za; video types mp4 mkv .+ \(from .+\\portable\\autofolder\.ini\)$'
            # 15 videos (one deleted by the driver), Episode 2.mkv playing: the 14 others minus the
            # longest run already in the new order on each side of it (worked out by hand: 6, 5, 6).
            '\[autofolder\] folder .+\\media\\: re-sorted by date-newest; re-added 8 items; \d+ moves$'
            '\[autofolder\] folder .+\\media\\: re-sorted by name-az; re-added 9 items; \d+ moves$'
            '\[autofolder\] autofolder\.ini line 1: unknown sort order "sideways" \(one of: .+\); using date-oldest$'
            '\[autofolder\] folder .+\\media\\: re-sorted by date-oldest; re-added 8 items; \d+ moves$'
            # A user's item plays: all 15 can be added again; the longest run in order (7) stays.
            '\[autofolder\] folder .+\\media\\: re-sorted by name-az; re-added 8 items; \d+ moves$'
        )
    }
    @{
        Name = 'settings-types'; Driver = 'test_settings'; Autofolder = $true; Files = @("it's here.mp4"); TimeoutSec = 30
        Config = 'scenario=[[types]]'; Settings = "# only these`r`nextensions=mp4, .AVI`r`n"
        LogMustMatch = @(
            '\[autofolder\] settings: sort date-oldest; video types mp4 avi \(from .+autofolder\.ini\)$'
            '\[autofolder\] folder .+\\media\\: 4 videos, 1 before and 2 after it.s here\.mp4; added 3, re-added 0, removed 0; 1 moves; \d+ ms \(scan \d+ ms\)$'
            '\[autofolder\] not a video file: .+\\media\\Episode 1\.mkv$'
        )
        LogMustNotMatch = @('\[autofolder\] autofolder\.ini line')
    }
    @{
        # The settings dialog (lua\extensions\), with a stand-in for VLC's dialog API.
        Name = 'dialog'; Driver = 'test_dialog'; Files = @(); TimeoutSec = 20
        LogMustMatch = @('\[autofolder\] dialog: saved sort name-az; video types mp4 mkv$')
    }
    # Building the folder from the first, a middle and the last video by date (16 videos, the
    # dot-name not counted), and from the dot-named one, which the scan itself skips. The move
    # counts are the fewest moves to the front for each case.
    @{
        Name = 'build-first'; Driver = 'test_build'; Autofolder = $true; Files = @('Episode 10.mkv'); TimeoutSec = 30
        LogMustMatch = @('\[autofolder\] folder .+: 16 videos, 0 before and 15 after Episode 10\.mkv; added 15, re-added 0, removed 0; 0 moves; \d+ ms \(scan \d+ ms\)$')
    }
    @{
        # The Japanese name: Unicode in the opened file and in the files added around it.
        Name = 'build-middle'; Driver = 'test_build'; Autofolder = $true; Files = @($testVideos[12]); TimeoutSec = 30
        LogMustMatch = @('\[autofolder\] folder .+: 16 videos, 12 before and 3 after .+; added 15, re-added 0, removed 0; 12 moves; \d+ ms \(scan \d+ ms\)$')
    }
    @{
        Name = 'build-last'; Driver = 'test_build'; Autofolder = $true; Files = @('attribute-hidden.mkv'); TimeoutSec = 30
        LogMustMatch = @('\[autofolder\] folder .+: 16 videos, 15 before and 0 after attribute-hidden\.mkv; added 15, re-added 0, removed 0; 15 moves; \d+ ms \(scan \d+ ms\)$')
    }
    @{
        Name = 'build-dot'; Driver = 'test_build'; Autofolder = $true; Files = @('.dot-hidden.mkv'); TimeoutSec = 30
        LogMustMatch = @('\[autofolder\] folder .+: 17 videos, 15 before and 1 after \.dot-hidden\.mkv; added 16, re-added 0, removed 0; 15 moves; \d+ ms \(scan \d+ ms\)$')
    }
    @{
        # A running VLC: the user's own item (a video in another folder) is in the playlist, then a
        # folder file is opened. The user's item stays first; it and 2 videos are moved. Clicking
        # the user's item afterwards builds nothing.
        Name = 'build-user'; Driver = 'test_build'; Autofolder = $true; Files = @(); TimeoutSec = 30
        Config = 'user=[[{0}]],open=[[Episode 1.mkv]]' -f (Join-Path $testRoot 'summer.mkv')
        LogMustMatch = @('\[autofolder\] folder .+: 16 videos, 2 before and 13 after Episode 1\.mkv; added 15, re-added 0, removed 0; 3 moves; \d+ ms \(scan \d+ ms\)$')
        LogMustNotMatch = @('\[autofolder\] left folder')
    }
    @{
        # Through a UNC path (\\127.0.0.1\C$\...): the folder is read and built through the share.
        Name = 'build-unc'; Driver = 'test_build'; Autofolder = $true; Unc = $true; Files = @(Join-Path $uncMedia 'Episode 2.mkv'); TimeoutSec = 30
        LogMustMatch = @('\[autofolder\] folder \\\\127\.0\.0\.1\\.+\\media\\: 16 videos, 1 before and 14 after Episode 2\.mkv; added 15, re-added 0, removed 0; 1 moves; \d+ ms \(scan \d+ ms\)$')
    }
    @{
        # 500 videos. The one opened is the last by date, so all 499 others are moved before it.
        Name = 'build-big'; Driver = 'test_big'; Autofolder = $true; Big = $true; Files = @(Join-Path $bigFolder $bigVideos[-1]); TimeoutSec = 40
        Config = 'list=[[{0}]]' -f $bigList
        LogMustMatch = @('\[autofolder\] folder .+\\big\\: 500 videos, 499 before and 0 after {0}; added 499, re-added 0, removed 0; 499 moves; \d+ ms \(scan \d+ ms\)$' -f [regex]::Escape($bigVideos[-1]))
    }
    # The playlist rules (test_rules.lua describes each scenario).
    @{
        Name = 'rules-switch'; Driver = 'test_rules'; Autofolder = $true; Files = @(); TimeoutSec = 40
        Config = 'scenario=[[switch]]'
        LogMustMatch = @(
            '\[autofolder\] folder .+\\media\\: 16 videos, 2 before and 13 after Episode 1\.mkv; added 15, re-added 0, removed 1; 3 moves; \d+ ms \(scan \d+ ms\)$'
            '\[autofolder\] left folder .+\\media\\: removed 15 items$'
            '\[autofolder\] folder .+\\Season 2\\: 2 videos, 0 before and 1 after Episode 1\.mkv; added 1, re-added 0, removed 0; 0 moves; \d+ ms \(scan \d+ ms\)$'
        )
    }
    @{
        Name = 'rules-refresh'; Driver = 'test_rules'; Autofolder = $true; Files = @(); TimeoutSec = 40
        Config = 'scenario=[[refresh]]'
        LogMustMatch = @(
            '\[autofolder\] folder .+\\refresh\\: 3 videos, 1 before and 1 after b\.mkv; added 2, re-added 0, removed 0; 1 moves; \d+ ms \(scan \d+ ms\)$'
            # a.mkv again: the old copy and c.mkv removed, b.mkv added again after the playing copy.
            '\[autofolder\] folder .+\\refresh\\: 3 videos, 0 before and 2 after a\.mkv; added 1, re-added 1, removed 2; 0 moves; \d+ ms \(scan \d+ ms\)$'
        )
        LogMustNotMatch = @('\[autofolder\] left folder')
    }
    @{
        # The user's report in To do 6: Episode 2.mkv opened again. The 14 videos after it by date
        # are added again behind the new copy, so nothing needs a move.
        Name = 'rules-reopen'; Driver = 'test_rules'; Autofolder = $true; Files = @('Episode 2.mkv'); TimeoutSec = 30
        Config = 'scenario=[[reopen]]'
        LogMustMatch = @(
            '\[autofolder\] folder .+\\media\\: 16 videos, 1 before and 14 after Episode 2\.mkv; added 15, re-added 0, removed 0; 1 moves; \d+ ms \(scan \d+ ms\)$'
            '\[autofolder\] folder .+\\media\\: 16 videos, 1 before and 14 after Episode 2\.mkv; added 0, re-added 14, removed 1; 0 moves; \d+ ms \(scan \d+ ms\)$'
        )
    }
    @{
        # Several files at once: the first plays, but it isn't the last item.
        Name = 'rules-several'; Driver = 'test_rules'; Autofolder = $true; Files = @('Episode 1.mkv', 'Episode 2.mkv'); TimeoutSec = 30
        Config = 'scenario=[[no-build]],expect=[[media\Episode 1.mkv | media\Episode 2.mkv]]'
        LogMustNotMatch = @('\[autofolder\] (left )?folder ')
    }
    @{
        # An .m3u (Episode 1.mkv, Episode 2.mkv): replaced by its entries, which aren't just opened.
        Name = 'rules-m3u'; Driver = 'test_rules'; Autofolder = $true; Files = @('playlist.m3u'); TimeoutSec = 30
        Config = 'scenario=[[no-build]],expect=[[media\Episode 1.mkv | media\Episode 2.mkv]]'
        LogMustNotMatch = @('\[autofolder\] (left )?folder ')
    }
    @{
        # Waits for core.JUST_OPENED_S (10 s) + 1 s.
        Name = 'rules-late'; Driver = 'test_rules'; Autofolder = $true; Files = @('Episode 2.mkv'); TimeoutSec = 45
        Config = 'scenario=[[late]]'
        LogMustMatch = @('\[autofolder\] item \d+ started, no build: added 1\d\.\d s before it started$')
        LogMustNotMatch = @('\[autofolder\] left folder', '\[autofolder\] folder .+Season 2')
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

    $settingsFile = Join-Path $portable 'autofolder.ini'
    if (Test-Path -LiteralPath $settingsFile) { Remove-Item -LiteralPath $settingsFile -Force }
    if ($Spec.Settings) { [IO.File]::WriteAllText($settingsFile, $Spec.Settings, (New-Object Text.UTF8Encoding($false))) }

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
    foreach ($pattern in $Spec.LogMustNotMatch) {
        $hits = @($logLines -match $pattern)
        if ($hits) { $problems.Add("log: a line matches /$pattern/: $($hits[0])") }
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
if ($selected | Where-Object { $_.Big }) { Initialize-BigFolder }

$failed = 0
foreach ($spec in $selected) {
    if ($spec.Unc -and -not (Test-Path -LiteralPath $uncMedia)) {
        # E.g. the admin share is off, or the account isn't a local administrator.
        Write-Host "SKIP $($spec.Name): $uncMedia can't be reached" -ForegroundColor Yellow
        continue
    }
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
