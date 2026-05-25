# Fetch or build arqma_flutter_solo_pool for Flutter desktop (Windows).
param(
    [ValidateSet("mingw")]
    [string]$Platform = "mingw",
    [string]$MsysRoot = ""
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$TauriBin = Join-Path $Root "rust\tauri-app\src-tauri\bin"
$Solo = Join-Path $TauriBin "arqma_flutter_solo_pool.exe"

if (Test-Path $Solo) {
    Write-Host "[fetch-or-build-solo-pool] already present: $Solo"
    exit 0
}

if ($env:ARQMA_SOLO_POOL_BUILD_FROM_SOURCE -ne "1") {
    try {
        & (Join-Path $PSScriptRoot "fetch-arqma-wallet-solo-pool-release.ps1") -Platforms "windows-x86_64-gnu"
        if (Test-Path $Solo) {
            Write-Host "[fetch-or-build-solo-pool] fetched -> $Solo"
            exit 0
        }
    } catch {
        Write-Warning "[fetch-or-build-solo-pool] fetch failed: $_"
    }
}

Write-Host "[fetch-or-build-solo-pool] building from source..."
if ([string]::IsNullOrWhiteSpace($MsysRoot)) {
    $MsysRoot = "C:\msys64"
}
& (Join-Path $Root "rust\tool\build_flutter_solo_pool.ps1") -MsysRoot $MsysRoot
if (-not (Test-Path $Solo)) {
    throw "missing $Solo after build"
}
Write-Host "[fetch-or-build-solo-pool] OK"
