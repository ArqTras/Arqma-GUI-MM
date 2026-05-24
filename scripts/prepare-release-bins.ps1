# Prepare rust/tauri-app/src-tauri/bin/ for a bundled release (arqmad only in bin).
# Usage (repo root):
#   .\scripts\prepare-release-bins.ps1              # copy only from .\bin if present
#   .\scripts\prepare-release-bins.ps1 -Download    # fetch latest GitHub release asset, then extract is manual on Windows — prefer placing exes in .\bin first
param (
  [switch] $Download
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

if ($Download) {
  Write-Host "[prepare-release-bins] running download-binaries.js (requires network)..."
  node (Join-Path $Root "build" "download-binaries.js")
  Write-Host "[prepare-release-bins] NOTE: extract the downloaded archive into repo .\bin\ (arqmad.exe) then re-run without -Download, or use ARQMA_BUILD_DIR at runtime."
}

Write-Host "[prepare-release-bins] copy-to-tauri-bins.js..."
node (Join-Path $Root "build" "copy-to-tauri-bins.js")

$dst = Join-Path $Root "rust" "tauri-app" "src-tauri" "bin"
if (-not (Test-Path (Join-Path $dst "arqmad.exe"))) {
  Write-Host "[prepare-release-bins] WARNING: missing $dst\arqmad.exe"
  Write-Host "  Add upstream-built arqmad, or rely on ARQMA_BUILD_DIR / ARQMA_DAEMON (see docs/WALLET_RUST_PORT.md)."
  exit 0
}
Write-Host "[prepare-release-bins] OK — arqmad.exe present under src-tauri/bin."
