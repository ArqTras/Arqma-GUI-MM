# Fetch or build arqma_flutter_solo_pool for Flutter desktop (Windows).
param(
    [ValidateSet("mingw")]
    [string]$Platform = "mingw",
    [string]$MsysRoot = ""
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$DesktopBin = Join-Path $Root "build\flutter-desktop-bin"
$Solo = Join-Path $DesktopBin "arqma_flutter_solo_pool.exe"

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

Write-Host "[fetch-or-build-solo-pool] fetching via build-flutter-solo-pool-for-desktop.sh (ArqTras/FFI)..."
& bash (Join-Path $Root "build/ci/build-flutter-solo-pool-for-desktop.sh") mingw
if (-not (Test-Path $Solo)) {
    throw "missing $Solo after fetch (set ARQMA_SOLO_POOL_BUILD_FROM_SOURCE=1 only with branch outdated source build)"
}
Write-Host "[fetch-or-build-solo-pool] OK"
