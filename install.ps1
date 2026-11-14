<#
.SYNOPSIS
    Installs vlc-autofolder into VLC 3.0 on Windows, or removes it with -Uninstall.

.DESCRIPTION
    Install (run it again to update):
    - Copies the Lua scripts from lua\ next to this script into VLC's user folder
      (%APPDATA%\vlc\lua\intf, \modules and \extensions).
    - Adds luaintf{intf=autofolder} to the extraintf setting in vlcrc, so VLC starts the script
      at every start. Other entries in extraintf are kept, and the global lua-intf setting isn't
      touched (chain syntax). A bare "lua" entry is removed: VLC's preferences page writes it in
      place of ours, and it starts VLC's command-line interface. It stays when a CLI host
      (rc-host, cli-host) is set, since then the CLI is used on purpose.
    Uninstall (-Uninstall, or uninstall.ps1):
    - Removes those files, the folders they leave empty, and autofolder.ini (the settings).
    - Removes only our entry (and a bare "lua", as above) from extraintf. When nothing else is
      left, the line goes back to VLC's default "#extraintf=".
    Both stop while any VLC runs: VLC may save vlcrc when it closes, which would undo the change.
    vlcrc is backed up as vlcrc.autofolder-YYYYMMDD-HHMMSS.bak before every change, and only the
    extraintf line changes: the BOM, the LF line endings and all other bytes stay as they are.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Messages for the person running the script, the errors in red.')]
[CmdletBinding()]
param(
    # VLC's user folder, which holds vlcrc. The tests pass a temporary folder.
    [string]$VlcDir = (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'vlc'),
    # Remove autofolder instead of installing it.
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

# The extraintf entry that starts autofolder. VLC splits extraintf at ":".
$entry = 'luaintf{intf=autofolder}'
# What VLC's preferences page (All > Interface > Main interfaces) writes in place of our entry:
# a bare "lua", which starts VLC's command-line interface instead (measured 2026-11-14).
$stray = 'lua'
$source = Join-Path $PSScriptRoot 'lua'
$luaDir = Join-Path $VlcDir 'lua'
$vlcrc = Join-Path $VlcDir 'vlcrc'
# Latin-1 turns every byte into one character and back, so the bytes this script doesn't edit
# (the BOM, UTF-8 or ANSI text, line endings) are written back unchanged.
$latin1 = [Text.Encoding]::GetEncoding(28591)

function Exit-Setup {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
    exit 1
}

function Get-AddonFile {
    # The add-on's files, relative to lua\ (e.g. intf\autofolder.lua).
    $prefix = (Get-Item -LiteralPath $source).FullName.TrimEnd('\') + '\'
    Get-ChildItem -LiteralPath $source -Recurse -File | ForEach-Object { $_.FullName.Substring($prefix.Length) }
}

function Get-ExtraintfEntry {
    # The entries of an "extraintf=" line, and the "`r" it ends with, if any.
    param([string]$Line)
    $null = $Line -match '^extraintf=(.*?)(\r?)$'
    @{ Entries = @($Matches[1].Split(':') | Where-Object { $_ }); End = $Matches[2] }
}

function Get-EditedVlcrc {
    # vlcrc's text with our entry added, or removed with -Remove, and what changed: Added and
    # Removed (our entry), Stray (a bare "lua" removed). The text is unchanged when there is
    # nothing to do. VLC reads every "extraintf=" line, in any section, and the last one wins
    # (measured 2026-11-12), and it compares setting names case-sensitively (measured). The
    # entries in a line are compared case-insensitively here (VLC's module names: not checked).
    param([string]$Text, [switch]$Remove)
    $edit = @{ Text = $Text; Added = $false; Removed = $false; Stray = $false }
    $lines = $Text.Split("`n")
    $set = @()        # the "extraintf=" lines
    $default = -1     # the first "#extraintf=": how VLC writes the default (empty) value
    $cliHost = $false # VLC writes both commented out ("#rc-host="); set, the CLI is used on purpose
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -cmatch '^extraintf=') { $set += $i }
        elseif ($default -lt 0 -and $lines[$i] -cmatch '^#extraintf=\r?$') { $default = $i }
        elseif ($lines[$i] -cmatch '^(rc|cli)-host=[^\r]') { $cliHost = $true }
    }
    $drop = @()  # the entries to take out
    if ($Remove) { $drop += $entry }
    if (-not $cliHost) { $drop += $stray }
    if ($Remove -or $set.Count) {
        # Uninstall cleans every line; install edits the line VLC uses.
        $edited = if ($Remove) { $set } else { $set[-1] }
        foreach ($i in $edited) {
            $line = Get-ExtraintfEntry $lines[$i]
            $old = $line.Entries
            $new = @($old | Where-Object { $drop -notcontains $_ })
            if (-not $Remove -and $new -notcontains $entry) { $new += $entry }
            if (($new -join ':') -ceq ($old -join ':')) { continue }
            if ($old -contains $stray -and $new -notcontains $stray) { $edit.Stray = $true }
            if ($old -contains $entry -and $new -notcontains $entry) { $edit.Removed = $true }
            if ($old -notcontains $entry -and $new -contains $entry) { $edit.Added = $true }
            $value = if ($new.Count) { 'extraintf=' + ($new -join ':') } else { '#extraintf=' }
            $lines[$i] = $value + $line.End
        }
    }
    elseif ($default -ge 0) {
        $end = if ($lines[$default].EndsWith("`r")) { "`r" } else { '' }
        $lines[$default] = "extraintf=$entry$end"
        $edit.Added = $true
    }
    else {
        # No extraintf line at all: add one at the end (VLC ignores sections, measured).
        if ($Text -and -not $Text.EndsWith("`n")) { $Text += "`n" }
        $edit.Text = $Text + "extraintf=$entry`n"
        $edit.Added = $true
        return $edit
    }
    $result = $lines -join "`n"
    # VLC cuts each line's last character as its line break, so an edited last line needs one.
    if ($result -cne $Text -and -not $result.EndsWith("`n")) { $result += "`n" }
    $edit.Text = $result
    $edit
}

function Save-Vlcrc {
    # Edits vlcrc with Get-EditedVlcrc, backing it up first. Returns what changed (see there).
    param([switch]$Remove)
    $old = $latin1.GetString([IO.File]::ReadAllBytes($vlcrc))
    $edit = Get-EditedVlcrc -Text $old -Remove:$Remove
    $new = $edit.Text
    if ($new -ceq $old) { return $edit }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $VlcDir "vlcrc.autofolder-$stamp.bak"
    for ($n = 2; Test-Path -LiteralPath $backup; $n++) { $backup = Join-Path $VlcDir "vlcrc.autofolder-$stamp-$n.bak" }
    Copy-Item -LiteralPath $vlcrc -Destination $backup
    Write-Host "Backed up vlcrc to $backup"
    # Written next to vlcrc and then swapped in, so vlcrc is never half-written.
    $temp = "$vlcrc.autofolder-new"
    [IO.File]::WriteAllBytes($temp, $latin1.GetBytes($new))
    [IO.File]::Replace($temp, $vlcrc, [NullString]::Value)
    $edit
}

function Write-VlcrcChange {
    # One line per change Save-Vlcrc made, or $Unchanged when it made none.
    param([hashtable]$Edit, [string]$Unchanged)
    if ($Edit.Stray) {
        Write-Host "vlcrc: removed `"$stray`" from extraintf (VLC's preferences page writes it in place of autofolder's entry; it starts VLC's command-line interface)"
    }
    if ($Edit.Removed) { Write-Host "vlcrc: removed $entry from extraintf" }
    if ($Edit.Added) { Write-Host "vlcrc: added $entry to extraintf" }
    if (-not ($Edit.Stray -or $Edit.Removed -or $Edit.Added)) { Write-Host $Unchanged }
}

if (Get-Process vlc -ErrorAction SilentlyContinue) {
    Exit-Setup 'VLC is running. Close every VLC window, then run this again.'
}
if (-not (Test-Path -LiteralPath (Join-Path $source 'intf\autofolder.lua'))) {
    Exit-Setup "The add-on's files are missing: there is no lua\intf\autofolder.lua next to this script ($PSScriptRoot)."
}
$files = @(Get-AddonFile)

if ($Uninstall) {
    $removed = 0
    foreach ($file in $files) {
        $target = Join-Path $luaDir $file
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force; $removed++ }
    }
    # The folders our files were in, deepest first, up to lua\ itself: removed when left empty.
    $folders = @(foreach ($file in $files) {
            $dir = Split-Path -Parent $file
            while ($dir) { Join-Path $luaDir $dir; $dir = Split-Path -Parent $dir }
        }) + $luaDir | Select-Object -Unique | Sort-Object Length -Descending
    foreach ($dir in $folders) {
        if ((Test-Path -LiteralPath $dir) -and -not (Get-ChildItem -LiteralPath $dir -Force)) {
            Remove-Item -LiteralPath $dir -Force
        }
    }
    Write-Host "Removed $removed files from $luaDir"
    $ini = Join-Path $VlcDir 'autofolder.ini'
    if (Test-Path -LiteralPath $ini) {
        Remove-Item -LiteralPath $ini -Force
        Write-Host "Removed the settings file $ini"
    }
    if (-not (Test-Path -LiteralPath $vlcrc -PathType Leaf)) {
        Write-Host "There is no vlcrc in $VlcDir, so there was no setting to remove."
    }
    else {
        Write-VlcrcChange (Save-Vlcrc -Remove) "vlcrc: extraintf didn't start autofolder (no change)"
    }
    Write-Host 'Uninstalled. VLC no longer starts autofolder.' -ForegroundColor Green
}
else {
    if (-not (Test-Path -LiteralPath $vlcrc -PathType Leaf)) {
        Exit-Setup ("VLC's settings file isn't there yet ($vlcrc). Start VLC once, click Continue " +
            'on its first-start question, close VLC, then run this again.')
    }
    foreach ($file in $files) {
        $target = Join-Path $luaDir $file
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $source $file) -Destination $target -Force
    }
    Write-Host "Copied $($files.Count) files to $luaDir"
    Write-VlcrcChange (Save-Vlcrc) 'vlcrc: extraintf already starts autofolder (no change)'
    Write-Host 'Installed. Start VLC and open a video: the other videos of its folder join the playlist.' -ForegroundColor Green
}
exit 0
