# Build Flutter Windows release and zip the runner output under .\dist\.
# Run from flutter\arqma_wallet_gui (or pass no args; script cds to its parent).
#
#   cd flutter\arqma_wallet_gui
#   .\tool\package_flutter_release.ps1

$ErrorActionPreference = "Stop"
$GuiRoot = Split-Path -Parent $PSScriptRoot
Set-Location $GuiRoot

if (-not (Test-Path "pubspec.yaml")) {
    Write-Error "pubspec.yaml not found; run from flutter/arqma_wallet_gui"
}

$versionLine = (Select-String -Path "pubspec.yaml" -Pattern "^\s*version:\s*(\S+)" | Select-Object -First 1).Matches.Groups[1].Value
if (-not $versionLine) { $versionLine = "0.0.0" }
$versionSafe = $versionLine -replace "\+", "-"

$dist = Join-Path $GuiRoot "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

flutter build windows --release

$releaseDir = Join-Path $GuiRoot "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
    Write-Error "Missing $releaseDir after build"
}

$zipName = "Arqma-Wallet-$versionSafe-windows-x64.zip"
$zipPath = Join-Path $dist $zipName
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $zipPath -Force
Write-Host "Packaged: $zipPath"
