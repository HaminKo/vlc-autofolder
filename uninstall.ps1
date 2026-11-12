<#
.SYNOPSIS
    Removes vlc-autofolder from VLC: runs install.ps1 -Uninstall (what it removes is
    described there).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
#>
[CmdletBinding()]
param(
    # VLC's user folder, which holds vlcrc. Default: %APPDATA%\vlc.
    [string]$VlcDir
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'install.ps1') @PSBoundParameters -Uninstall
exit $LASTEXITCODE
