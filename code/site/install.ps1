# install.ps1 — Downloads and installs the latest DocMD CLI release on Windows.
#
# Usage:
#   irm https://docmd.ccisne.dev/install.ps1 | iex

$ErrorActionPreference = 'Stop'

$repo = 'ccisnedev/docmd'
$installDir = Join-Path $env:LOCALAPPDATA 'docmd'
$binDir = Join-Path $installDir 'bin'
$executableName = 'docmd.exe'
$aliasName = 'dm.exe'

if ($env:OS -ne 'Windows_NT') {
    Write-Error 'DocMD CLI install.ps1 is for Windows only.'
    exit 1
}

if ([System.Environment]::Is64BitOperatingSystem -eq $false) {
    Write-Error 'DocMD CLI requires a 64-bit operating system.'
    exit 1
}

Write-Host '>>> Fetching latest release...'
$releaseUrl = "https://api.github.com/repos/$repo/releases/latest"
$headers = @{ Accept = 'application/vnd.github+json' }
$release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers
$asset = $release.assets | Where-Object { $_.name -eq 'docmd-windows-x64.exe' } | Select-Object -First 1

if (-not $asset) {
    Write-Error "No docmd-windows-x64.exe asset found in release $($release.tag_name)."
    exit 1
}

Write-Host "    Release: $($release.tag_name)"
Write-Host "    Asset:   $($asset.name)"

# The release asset is the raw compiled executable, not an archive:
# InstallationPlugin's `upgrade` command writes it directly over
# $binDir\$executableName's current location, so the installer does the
# equivalent here on first install.
New-Item -ItemType Directory -Path $binDir -Force | Out-Null
$targetPath = Join-Path $binDir $executableName
$tempExe = Join-Path $env:TEMP "docmd-$($release.tag_name).exe"

Write-Host '>>> Downloading...'
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempExe

# Atomic-ish swap: write to a temp path, then move into place, so a
# still-running docmd.exe is never truncated mid-write.
Move-Item -Path $tempExe -Destination $targetPath -Force

# `dm` is a short alias for `docmd`. It is a hard link, not a copy, so
# `docmd doctor`'s alias check (which compares them by file identity) sees
# them as the same binary.
$aliasPath = Join-Path $binDir $aliasName
if (Test-Path $aliasPath) {
    Remove-Item $aliasPath -Force
}
New-Item -ItemType HardLink -Path $aliasPath -Value $targetPath | Out-Null
Write-Host ">>> Alias configured: $aliasPath -> $executableName"

$userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath -notlike "*$binDir*") {
    Write-Host '>>> Adding docmd\bin to PATH...'
    [System.Environment]::SetEnvironmentVariable('PATH', "$userPath;$binDir", 'User')
    $env:PATH = "$env:PATH;$binDir"
}

Write-Host '>>> Verifying installation...'
$versionOutput = & $targetPath version
Write-Host "    $versionOutput"

Write-Host ''
Write-Host '>>> DocMD CLI installed successfully!'
Write-Host "    Location: $installDir"
