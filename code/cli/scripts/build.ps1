Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cliDir = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $cliDir 'build'
$binDir = Join-Path $buildDir 'bin'

Push-Location $cliDir
try {
    if (Test-Path $buildDir) { Remove-Item $buildDir -Recurse -Force }
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null

    Write-Host '>>> dart compile exe' -ForegroundColor Cyan
    dart compile exe bin/main.dart -o "$binDir\docmd.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }

    Write-Host "`nBuild complete: $buildDir" -ForegroundColor Green
}
finally {
    Pop-Location
}
