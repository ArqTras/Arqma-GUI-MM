# Prepare rust/tauri-app/src-tauri/bin/ for a bundled release (arqmad + arqma-wallet-rpc).
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
  Write-Host "[prepare-release-bins] NOTE: extract the downloaded archive into repo .\bin\ (arqmad.exe, arqma-wallet-rpc.exe) then re-run without -Download, or use ARQMA_BUILD_DIR at runtime."
}

Write-Host "[prepare-release-bins] copy-to-tauri-bins.js..."
node (Join-Path $Root "build" "copy-to-tauri-bins.js")

$dst = Join-Path $Root "rust" "tauri-app" "src-tauri" "bin"
$need = @("arqmad.exe", "arqma-wallet-rpc.exe")
$missing = @()
foreach ($n in $need) {
  if (-not (Test-Path (Join-Path $dst $n))) { $missing += $n }
}
if ($missing.Count -gt 0) {
  Write-Host "[prepare-release-bins] WARNING: missing in $dst : $($missing -join ', ')"
  Write-Host "  Add upstream-built files, or rely on ARQMA_BUILD_DIR / ARQMA_WALLET_RPC / ARQMA_DAEMON (see docs/WALLET_RUST_PORT.md)."
  exit 0
}
Write-Host "[prepare-release-bins] OK — wallet + daemon exes present under src-tauri/bin."
