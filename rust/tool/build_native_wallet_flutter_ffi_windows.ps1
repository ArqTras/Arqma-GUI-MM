# Build Arqma MinGW wallet_merged + arqma-wallet-flutter-ffi.dll (native wallet, no arqma-wallet-rpc).
# Linux/macOS (same static-hybrid intent): export ARQMA_WALLET_FFI_STATIC_HYBRID=1 then
# `cargo build -p arqma-wallet-flutter-ffi --release` from `rust/` (see rust/tool/flutter-ffi-static-hybrid-build.sh).
# Prereqs: MSYS2 MINGW64 packages per .github/workflows/desktop-release.yml (job tauri, Windows), rustup target x86_64-pc-windows-gnu.
param(
    [string]$MsysRoot = "C:\msys64",
    [switch]$SkipArqmaCMake,
    [switch]$SkipFlutter,
    [switch]$SkipSoloPool,
    # Experimental: static libgcc/libstdc++ + static Boost/OpenSSL/...; ICU stays dynamic (see arqma-wallet-flutter-ffi build.rs).
    [switch]$StaticHybridFfi
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$rustRoot = Join-Path $repoRoot "rust"

$env:Path = "$MsysRoot\mingw64\bin;$MsysRoot\usr\bin;" + $env:Path
$env:ARQMA_WALLET2_MSYS_ROOT = "$MsysRoot\mingw64"
$env:ARQMA_MINGW_BIN = "$MsysRoot\mingw64\bin"
$env:ARQMA_WALLET2_UPSTREAM_DIR = Join-Path $rustRoot "arqma-rpc-upstream"
if (-not $env:CARGO_PROFILE_RELEASE_LTO) { $env:CARGO_PROFILE_RELEASE_LTO = "thin" }
if ($StaticHybridFfi) {
    $env:ARQMA_WALLET_FFI_STATIC_HYBRID = "1"
    Write-Host "ARQMA_WALLET_FFI_STATIC_HYBRID=1 (experimental static-hybrid FFI link)"
} else {
    Remove-Item Env:ARQMA_WALLET_FFI_STATIC_HYBRID -ErrorAction SilentlyContinue
}

Push-Location $repoRoot
try {
    if (-not $SkipArqmaCMake) {
        & bash (Join-Path $repoRoot "build/ci/build-arqma-mingw.sh")
        if ($LASTEXITCODE -ne 0) { throw "build-arqma-mingw.sh failed (exit $LASTEXITCODE)" }
    }
} finally {
    Pop-Location
}

Push-Location $rustRoot
try {
    cargo build -p arqma-wallet-flutter-ffi --release --target x86_64-pc-windows-gnu
    if ($LASTEXITCODE -ne 0) { throw "cargo build arqma-wallet-flutter-ffi failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

$dll = Join-Path $rustRoot "target\x86_64-pc-windows-gnu\release\arqma_wallet_flutter_ffi.dll"
if (-not (Test-Path $dll)) { throw "Missing $dll" }
Write-Host "OK: $dll"

if (-not $SkipSoloPool) {
    & bash (Join-Path $repoRoot "build/ci/build-flutter-solo-pool-for-desktop.sh") mingw
}

if (-not $SkipFlutter) {
    $flutterBat = $null
    foreach ($c in @(
            "$env:LOCALAPPDATA\puro\envs\stable\flutter\bin\flutter.bat",
            "$env:USERPROFILE\flutter-sdk\flutter\bin\flutter.bat",
            "$env:USERPROFILE\development\flutter\bin\flutter.bat",
            "C:\src\flutter\bin\flutter.bat"
        )) {
        if ($c -and (Test-Path $c)) { $flutterBat = $c; break }
    }
    if (-not $flutterBat) {
        $cmd = Get-Command flutter.bat -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { $flutterBat = $cmd.Source }
    }
    if (-not $flutterBat) { $flutterBat = "flutter" }
    $gui = Join-Path $repoRoot "flutter\arqma_wallet_gui"
    Push-Location $gui
    try {
        & $flutterBat pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed (exit $LASTEXITCODE)" }
        & $flutterBat build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
}
