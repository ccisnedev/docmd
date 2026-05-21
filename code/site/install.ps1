# install.ps1 — Downloads and installs the latest DocMD CLI release on Windows.
#
# Usage:
#   irm https://docmd.ccisne.dev/install.ps1 | iex

$ErrorActionPreference = 'Stop'

$repo = 'ccisnedev/docmd'
$installDir = Join-Path $env:LOCALAPPDATA 'docmd'
$binDir = Join-Path $installDir 'bin'

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
$asset = $release.assets | Where-Object { $_.name -eq 'docmd-windows-x64.zip' } | Select-Object -First 1

if (-not $asset) {
    Write-Error "No docmd-windows-x64.zip asset found in release $($release.tag_name)."
    exit 1
}

Write-Host "    Release: $($release.tag_name)"
Write-Host "    Asset:   $($asset.name)"

$tempZip = Join-Path $env:TEMP "docmd-$($release.tag_name).zip"

Write-Host '>>> Downloading...'
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempZip

if (Test-Path $installDir) {
    Write-Host '>>> Removing previous installation...'
    Remove-Item -Recurse -Force $installDir
}

Write-Host '>>> Extracting...'
Expand-Archive -Path $tempZip -DestinationPath $installDir -Force
Remove-Item $tempZip

$userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath -notlike "*$binDir*") {
    Write-Host '>>> Adding docmd\bin to PATH...'
    [System.Environment]::SetEnvironmentVariable('PATH', "$userPath;$binDir", 'User')
    $env:PATH = "$env:PATH;$binDir"
}

Write-Host '>>> Verifying installation...'
$versionOutput = & (Join-Path $binDir 'docmd.exe') version
Write-Host "    $versionOutput"

Write-Host ''
Write-Host '>>> DocMD CLI installed successfully!'
Write-Host "    Location: $installDir"