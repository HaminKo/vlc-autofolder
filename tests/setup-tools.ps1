<#
.SYNOPSIS
    Downloads the development tools into tools\ (gitignored).

.DESCRIPTION
    - A portable VLC 3.0.24 (win64 zip from videolan.org) in tools\vlc\, with an empty
      tools\vlc\portable\ folder. With that folder present, VLC keeps its settings and
      Lua user folder there instead of in %APPDATA%\vlc, so tests never touch the real VLC.
    - luacheck.exe v1.2.0 (Lua linter) in tools\.
    Both downloads are checked against pinned SHA-256 hashes.
    Run once per PC. Running it again skips what is already there, unless -Force is given.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tests\setup-tools.ps1
#>
[CmdletBinding()]
param(
    # Download and unpack again even if the tools are already there.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # the progress bar makes Invoke-WebRequest very slow in PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$tools = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools'

$vlcVersion = '3.0.24'
# Not get.videolan.org: it answers PowerShell's browser-like user agent with an HTML mirror page.
$vlcUrl = "https://download.videolan.org/pub/videolan/vlc/$vlcVersion/win64/vlc-$vlcVersion-win64.zip"
$vlcSha256 = 'fcf30850371ad10c9373cc4f0f4501e7dee49e3e9ae9f20c72fb2661a1ca6323'  # from VideoLAN's .sha256 file

$luacheckUrl = 'https://github.com/lunarmodules/luacheck/releases/download/v1.2.0/luacheck.exe'
$luacheckSha256 = '0f1c69c4d09f1ebb4d8df14c215e4553e2e639bd4cb7bf3c639b0daa6198317b'  # measured 2026-11-10

function Get-CheckedFile {
    param([string]$Url, [string]$Destination, [string]$Sha256)
    # Downloads to a temporary name first, so a failed or wrong download never sits at
    # $Destination looking installed.
    Write-Output "Downloading $Url"
    $partial = "$Destination.download"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $partial -UseBasicParsing
        $actual = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
        if ($actual -ne $Sha256) {
            throw "SHA-256 mismatch for $Url`n  expected $Sha256`n  got      $actual"
        }
        Move-Item -LiteralPath $partial -Destination $Destination -Force
    }
    finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial }
    }
}

New-Item -ItemType Directory -Force -Path $tools | Out-Null

# Portable VLC
$vlcDir = Join-Path $tools 'vlc'
$vlcExe = Join-Path $vlcDir 'vlc.exe'
if ($Force -or -not (Test-Path -LiteralPath $vlcExe)) {
    if (Get-Process vlc -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $vlcExe }) {
        throw "The test VLC ($vlcExe) is running. Close it first."
    }
    $zip = Join-Path $tools "vlc-$vlcVersion-win64.zip"
    Get-CheckedFile -Url $vlcUrl -Destination $zip -Sha256 $vlcSha256
    $unpack = Join-Path $tools 'vlc-unpack'
    if (Test-Path -LiteralPath $unpack) { Remove-Item -LiteralPath $unpack -Recurse -Force }
    Write-Output "Unpacking to $vlcDir"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $unpack)
    if (Test-Path -LiteralPath $vlcDir) { Remove-Item -LiteralPath $vlcDir -Recurse -Force }
    Move-Item -LiteralPath (Join-Path $unpack "vlc-$vlcVersion") -Destination $vlcDir
    Remove-Item -LiteralPath $unpack -Recurse -Force
    Remove-Item -LiteralPath $zip
}
New-Item -ItemType Directory -Force -Path (Join-Path $vlcDir 'portable') | Out-Null
# The plugin cache, as VLC's installer creates it; without it VLC scans every plugin at each start.
if (-not (Test-Path -LiteralPath (Join-Path $vlcDir 'plugins\plugins.dat'))) {
    & (Join-Path $vlcDir 'vlc-cache-gen.exe') (Join-Path $vlcDir 'plugins')
    if ($LASTEXITCODE -ne 0) { throw "vlc-cache-gen.exe failed with exit code $LASTEXITCODE" }
}
Write-Output ("VLC: {0} ({1})" -f $vlcExe, (Get-Item -LiteralPath $vlcExe).VersionInfo.ProductVersion)

# luacheck
$luacheck = Join-Path $tools 'luacheck.exe'
if ($Force -or -not (Test-Path -LiteralPath $luacheck)) {
    Get-CheckedFile -Url $luacheckUrl -Destination $luacheck -Sha256 $luacheckSha256
}
Write-Output "luacheck: $luacheck"
