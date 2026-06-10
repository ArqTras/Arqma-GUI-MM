# Build arqma_wallet_flutter_ffi.dll for Windows CI (MinGW-gnu) from this repo's rust/ tree.
# Replaces fetch-arqma-wallet-ffi-release.ps1 when the prebuilt DLL has stale link flags (e.g. duplicate LMDB).
param(
    [string]$MsysRoot = "C:\msys64"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$rustRoot = Join-Path $root "rust"
$tauriApp = Join-Path $rustRoot "tauri-app"

if (-not (Test-Path $MsysRoot)) { throw "MSYS2 not found at $MsysRoot" }

$env:Path = "$MsysRoot\mingw64\bin;$MsysRoot\usr\bin;" + $env:Path
$env:ARQMA_WALLET2_MSYS_ROOT = "$MsysRoot\mingw64"
$env:ARQMA_MINGW_BIN = "$MsysRoot\mingw64\bin"
$env:ARQMA_WALLET2_UPSTREAM_DIR = Join-Path $rustRoot "arqma-rpc-upstream"
if (-not $env:CARGO_PROFILE_RELEASE_LTO) { $env:CARGO_PROFILE_RELEASE_LTO = "thin" }

if ($env:GITHUB_ACTIONS -eq "true" -and $env:GITHUB_PATH) {
    $cargoBin = Join-Path $env:USERPROFILE ".cargo\bin"
    if (Test-Path $cargoBin) {
        "$cargoBin" | Out-File -FilePath $env:GITHUB_PATH -Append -Encoding utf8
        $env:Path = "$cargoBin;" + $env:Path
    }
}

Push-Location $tauriApp
try {
    npm run build:arqma:mingw
    if ($LASTEXITCODE -ne 0) { throw "npm run build:arqma:mingw failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

Push-Location $rustRoot
try {
    rustup target add x86_64-pc-windows-gnu 2>$null | Out-Null
    cargo build -p arqma-wallet-flutter-ffi --release --target x86_64-pc-windows-gnu
    if ($LASTEXITCODE -ne 0) { throw "cargo build arqma-wallet-flutter-ffi failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

$dll = Join-Path $rustRoot "target\x86_64-pc-windows-gnu\release\arqma_wallet_flutter_ffi.dll"
if (-not (Test-Path $dll)) { throw "Missing $dll after build" }
Write-Host "OK: built Windows FFI from source -> $dll"
