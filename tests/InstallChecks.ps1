<#
.SYNOPSIS
    Checks of install.ps1, uninstall.ps1 and their double-click .cmd files, for run-tests.ps1.
    Dot-source it after TestCommon.ps1.

.DESCRIPTION
    - Test-InstallScript: install and uninstall against small vlcrc files in
      %TEMP%\vlc-autofolder-tests\install\ (no VLC); the .cmd files run in cmd.exe.
    - Initialize-InstalledPortable: the test VLC's user folder as install.ps1 leaves it, for
      the case where VLC loads autofolder through vlcrc.
    Both run the scripts in this process; they refuse to run while any VLC is open.
#>

$installScript = Join-Path $root 'install.ps1'
$uninstallScript = Join-Path $root 'uninstall.ps1'
# vlcrc texts are handled as Latin-1, one character per byte, like install.ps1 does.
$latin1 = [Text.Encoding]::GetEncoding(28591)

function Invoke-SetupScript {
    # Runs install.ps1 or uninstall.ps1; returns its exit code and its messages.
    param([string]$Script, [string]$VlcDir)
    $text = & $Script -VlcDir $VlcDir *>&1 | Out-String
    @{ Code = $LASTEXITCODE; Text = $text.Trim() }
}

function Invoke-CmdScript {
    # Runs install.cmd or uninstall.cmd in cmd.exe like a double-click, with an empty input so
    # its "pause" returns at once; returns its exit code and its output.
    param([string]$Script, [string]$VlcDir)
    $emptyInput = Join-Path $testRoot 'install\empty-input.txt'
    $output = Join-Path $testRoot 'install\cmd-output.txt'
    $errors = Join-Path $testRoot 'install\cmd-errors.txt'
    [IO.File]::WriteAllText($emptyInput, '')
    # cmd /c drops the first and the last quote of ""script" -VlcDir "dir"".
    $process = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"`"$Script`" -VlcDir `"$VlcDir`"`"" `
        -RedirectStandardInput $emptyInput -RedirectStandardOutput $output -RedirectStandardError $errors -NoNewWindow -Wait -PassThru
    # Console programs write redirected output in the console's code page.
    $text = [IO.File]::ReadAllText($output, [Console]::OutputEncoding) + [IO.File]::ReadAllText($errors, [Console]::OutputEncoding)
    @{ Code = $process.ExitCode; Text = $text.Trim() }
}

function Get-CheckLine {
    # A result line in the drivers' format (testlib.lua).
    param([string]$Name, [bool]$Ok, [string]$Message)
    if ($Ok) { "ok $Name" } else { "fail ${Name}: $Message" }
}

function Compare-VlcrcText {
    # A result line: the vlcrc in $Dir has the text $Expected, byte for byte.
    param([string]$Name, [string]$Dir, [string]$Expected)
    $actual = $latin1.GetString([IO.File]::ReadAllBytes((Join-Path $Dir 'vlcrc')))
    if ($actual -ceq $Expected) { return "ok $Name" }
    $a = $actual.Split("`n"); $e = $Expected.Split("`n")
    for ($i = 0; $i -lt [Math]::Max($a.Length, $e.Length); $i++) {
        if ($a[$i] -cne $e[$i]) { return "fail ${Name}: line $($i + 1) is [$($a[$i])], expected [$($e[$i])]" }
    }
}

function Get-TestVlcrc {
    # A short vlcrc like VLC writes it (BOM, LF, sections), with $Extraintf as the extraintf
    # line(s). Non-ASCII bytes (UTF-8 e-acute) and a similar setting must stay untouched.
    param([string]$Extraintf)
    $bom = $latin1.GetString([byte[]](0xEF, 0xBB, 0xBF))
    $eAcute = $latin1.GetString([byte[]](0xC3, 0xA9))
    $bom + "###`n###  vlc 3.0.24`n###`n`n[lua] # Lua interpreter`n`n# Lua interface (string)`n#lua-intf=dummy`n`n" +
    "[ntservice] # Windows Service interface`n`n# Extra interface modules (string)`nntservice-extraintf=http`n`n" +
    "[core] # core program`n`n# Extra interface modules (string)`n$Extraintf`n`n# Control interfaces (string)`n#control=`n`n" +
    "[qt] # Qt interface`n`nqt-privacy-ask=0`nsnapshot-path=C:\Users\caf$eAcute\Pictures`n"
}

function Get-BackupCount {
    param([string]$Dir)
    @(Get-ChildItem -LiteralPath $Dir -Filter 'vlcrc.autofolder-*.bak').Count
}

function Test-InstallScript {
    # Result lines for run-tests.ps1's Check field: the number of passed checks, then each
    # failed one, then "done".
    $lines = @(Get-InstallCheckLine)
    'info {0} checks passed' -f @($lines -like 'ok *').Count
    $lines -notlike 'ok *'
}

function Get-InstallCheckLine {
    # A result line (ok / fail) per check, then "done".
    $base = Join-Path $testRoot 'install'
    $ours = 'extraintf=luaintf{intf=autofolder}'
    $none = (Get-TestVlcrc '# (no extraintf line)').TrimEnd("`n")  # and no line break at the end
    # The vlcrc before install, after install, and after uninstall.
    $variants = @(
        @{ Name = 'default'; Before = '#extraintf='; Installed = $ours; Uninstalled = '#extraintf=' }
        @{ Name = 'empty'; Before = 'extraintf='; Installed = $ours; Uninstalled = '#extraintf=' }
        @{ Name = 'other'; Before = 'extraintf=http'; Installed = 'extraintf=http:luaintf{intf=autofolder}'; Uninstalled = 'extraintf=http' }
        @{ Name = 'installed'; Before = $ours; Installed = $ours; Uninstalled = '#extraintf=' }
        @{ Name = 'among'; Before = 'extraintf=http:luaintf{intf=autofolder}:oldrc'; Installed = 'extraintf=http:luaintf{intf=autofolder}:oldrc'; Uninstalled = 'extraintf=http:oldrc' }
        # VLC uses the last line, so ours goes there.
        @{ Name = 'two-lines'; Before = "extraintf=http`n`nextraintf="; Installed = "extraintf=http`n`n$ours"; Uninstalled = "extraintf=http`n`n#extraintf=" }
        # VLC compares names case-sensitively, so it ignores "ExtraIntf=", and so must we.
        @{ Name = 'case'; Before = "#extraintf=`nExtraIntf=x"; Installed = "$ours`nExtraIntf=x"; Uninstalled = "#extraintf=`nExtraIntf=x" }
    ) | ForEach-Object {
        @{ Name = $_.Name; Before = Get-TestVlcrc $_.Before; Installed = Get-TestVlcrc $_.Installed; Uninstalled = Get-TestVlcrc $_.Uninstalled }
    }
    $variants += @{ Name = 'none'; Before = $none; Installed = "$none`n$ours`n"; Uninstalled = "$none`n#extraintf=`n" }
    # The extraintf line last, with no line break: install adds one (VLC cuts a line's last character).
    $variants += @{ Name = 'last-line'; Before = "$none`nextraintf=http"; Installed = "$none`nextraintf=http:luaintf{intf=autofolder}`n"; Uninstalled = "$none`nextraintf=http`n" }

    $sourceLua = Join-Path $root 'lua'
    $addonFiles = @(Get-RelativeFile $sourceLua)

    foreach ($v in $variants) {
        $n = $v.Name
        $dir = Join-Path $base $n
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $dir 'vlcrc'), $latin1.GetBytes($v.Before))
        $changes = [int]($v.Installed -cne $v.Before)
        if ($n -eq 'default') {
            # Another add-on's script: install and uninstall leave it alone.
            New-Item -ItemType Directory -Force -Path (Join-Path $dir 'lua\intf') | Out-Null
            [IO.File]::WriteAllText((Join-Path $dir 'lua\intf\other.lua'), "-- not ours`n")
        }

        $r = Invoke-SetupScript $installScript $dir
        Get-CheckLine "$n install exit code" ($r.Code -eq 0) "$($r.Code): $($r.Text)"
        Compare-VlcrcText "$n install vlcrc" $dir $v.Installed
        Get-CheckLine "$n install backups" ((Get-BackupCount $dir) -eq $changes) "$(Get-BackupCount $dir), expected $changes"
        if ($changes) {
            $backup = Get-ChildItem -LiteralPath $dir -Filter 'vlcrc.autofolder-*.bak' | Select-Object -First 1
            $same = $latin1.GetString([IO.File]::ReadAllBytes($backup.FullName)) -ceq $v.Before
            Get-CheckLine "$n backup is the old vlcrc" $same $backup.Name
        }
        $missing = @($addonFiles | Where-Object {
                $target = Join-Path $dir "lua\$_"
                -not (Test-Path -LiteralPath $target) -or
                (Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath (Join-Path $sourceLua $_)).Hash
            })
        Get-CheckLine "$n install copies the files" (-not $missing) "missing or different: $($missing -join ', ')"

        $r = Invoke-SetupScript $installScript $dir
        Get-CheckLine "$n install again exit code" ($r.Code -eq 0) "$($r.Code): $($r.Text)"
        Compare-VlcrcText "$n install again changes nothing" $dir $v.Installed
        Get-CheckLine "$n install again makes no backup" ((Get-BackupCount $dir) -eq $changes) "$(Get-BackupCount $dir), expected $changes"

        if ($n -eq 'default') { [IO.File]::WriteAllText((Join-Path $dir 'autofolder.ini'), "sort=name-az`n") }
        $r = Invoke-SetupScript $uninstallScript $dir
        Get-CheckLine "$n uninstall exit code" ($r.Code -eq 0) "$($r.Code): $($r.Text)"
        Compare-VlcrcText "$n uninstall vlcrc" $dir $v.Uninstalled
        $changes += [int]($v.Uninstalled -cne $v.Installed)
        Get-CheckLine "$n uninstall backups" ((Get-BackupCount $dir) -eq $changes) "$(Get-BackupCount $dir), expected $changes"
        $left = (Get-ChildItem -LiteralPath $dir -Recurse -Force | ForEach-Object { $_.FullName.Substring($dir.Length + 1) } |
                Where-Object { $_ -ne 'vlcrc' -and $_ -notlike 'vlcrc.autofolder-*.bak' } | Sort-Object) -join ', '
        $want = if ($n -eq 'default') { 'lua, lua\intf, lua\intf\other.lua' } else { '' }
        Get-CheckLine "$n uninstall leaves only what isn't ours" ($left -eq $want) "left: [$left], expected [$want]"
    }

    # No vlcrc yet: install stops before copying anything; uninstall has nothing to do.
    $dir = Join-Path $base 'no-vlcrc'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $r = Invoke-SetupScript $installScript $dir
    Get-CheckLine 'no vlcrc: install stops' ($r.Code -eq 1 -and $r.Text -match 'Start VLC once') "$($r.Code): $($r.Text)"
    Get-CheckLine 'no vlcrc: nothing copied' (-not (Get-ChildItem -LiteralPath $dir -Force)) 'the folder is not empty'
    $r = Invoke-SetupScript $uninstallScript $dir
    Get-CheckLine 'no vlcrc: uninstall exit code' ($r.Code -eq 0) "$($r.Code): $($r.Text)"

    # The double-click files: the arguments and the exit code pass through, and "pause" runs
    # (its prompt, in the Windows language, is a line after install.ps1's last one).
    $r = Invoke-CmdScript (Join-Path $root 'install.cmd') $dir
    Get-CheckLine 'no vlcrc: install.cmd exit code' ($r.Code -eq 1) "$($r.Code): $($r.Text)"
    $dir = Join-Path $base 'cmd'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $dir 'vlcrc'), $latin1.GetBytes((Get-TestVlcrc '#extraintf=')))
    $r = Invoke-CmdScript (Join-Path $root 'install.cmd') $dir
    Get-CheckLine 'install.cmd exit code and pause' ($r.Code -eq 0 -and $r.Text -match 'Installed\..*\n.') "$($r.Code): $($r.Text)"
    Compare-VlcrcText 'install.cmd vlcrc' $dir (Get-TestVlcrc $ours)
    $r = Invoke-CmdScript (Join-Path $root 'uninstall.cmd') $dir
    Get-CheckLine 'uninstall.cmd exit code' ($r.Code -eq 0) "$($r.Code): $($r.Text)"
    Compare-VlcrcText 'uninstall.cmd vlcrc' $dir (Get-TestVlcrc '#extraintf=')
    # Alone in a folder, as when it's double-clicked inside Explorer's zip view.
    $dir = Join-Path $base 'zip-view'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'install.cmd') -Destination $dir
    $r = Invoke-CmdScript (Join-Path $dir 'install.cmd') $dir
    Get-CheckLine 'install.cmd alone says to extract the zip' ($r.Code -eq 1 -and $r.Text -match 'extract it first') "$($r.Code): $($r.Text)"
    'done'
}

function Initialize-InstalledPortable {
    # The portable folder after a real install: VLC's own default vlcrc (written by the test VLC
    # with --reset-config), then install.ps1, then the test drivers from tests\lua\.
    if (Test-Path -LiteralPath $portable) { Remove-Item -LiteralPath $portable -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $portable | Out-Null
    $process = Start-Process -FilePath $vlcExe -PassThru -WindowStyle Hidden -ArgumentList @(
        '--reset-config', '-I', 'dummy', '--dummy-quiet', '--no-crashdump', '--no-media-library'
        '--no-one-instance', '--no-one-instance-when-started-from-file', 'vlc://quit')
    if (-not $process.WaitForExit(30000)) { Stop-Process -Id $process.Id -Force; throw 'VLC --reset-config did not exit within 30 s' }
    if (-not (Test-Path -LiteralPath (Join-Path $portable 'vlcrc'))) { throw 'VLC --reset-config wrote no vlcrc' }
    $r = Invoke-SetupScript $installScript $portable
    if ($r.Code -ne 0) { throw "install.ps1 failed ($($r.Code)): $($r.Text)" }
    Copy-LuaFolder -Source (Join-Path $root 'tests\lua') -Target (Join-Path $portable 'lua')
}
