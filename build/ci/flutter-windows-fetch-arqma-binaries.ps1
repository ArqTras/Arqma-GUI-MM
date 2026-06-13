# Fetch arqmad.exe from arqma/arqma GitHub Releases into build/flutter-desktop-bin/
# (same source as build/download-binaries.js). Only arqmad — no arqma-wallet-rpc in bin.
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$dst = Join-Path $root "build\flutter-desktop-bin"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Push-Location $root
try {
  node build/download-binaries.js
} finally {
  Pop-Location
}
$zip = Join-Path $root "downloads\latest.zip"
if (-not (Test-Path $zip)) { throw "missing $zip after download-binaries.js" }
$exdir = Join-Path $root "downloads\extract-ci-flutter-win"
if (Test-Path $exdir) { Remove-Item -Recurse -Force $exdir }
Expand-Archive -LiteralPath $zip -DestinationPath $exdir -Force
$mad = Get-ChildItem -Path $exdir -Recurse -Filter "arqmad.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $mad) { throw "arqmad.exe not found under $exdir" }
Copy-Item -LiteralPath $mad.FullName -Destination (Join-Path $dst "arqmad.exe") -Force
Get-ChildItem $dst | Format-Table Name, Length
