# Fetch arqmad.exe (+ arqma-wallet-rpc.exe when present) from arqma/arqma GitHub Releases
# into rust/tauri-app/src-tauri/bin/ — same source as build/download-binaries.js (Tauri CI).
# Avoids MinGW linking issues for daemon/wallet_rpc_server in Flutter Windows jobs.
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$dst = Join-Path $root "rust\tauri-app\src-tauri\bin"
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
$wr = Get-ChildItem -Path $exdir -Recurse -Filter "arqma-wallet-rpc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $wr) {
  Write-Host "::notice::arqma-wallet-rpc.exe not in upstream archive — CI will build wallet_rpc_server from source (next step)."
} else {
  Copy-Item -LiteralPath $wr.FullName -Destination (Join-Path $dst "arqma-wallet-rpc.exe") -Force
}
Get-ChildItem $dst | Format-Table Name, Length
