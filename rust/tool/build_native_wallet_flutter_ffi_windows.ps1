# Build Arqma MinGW wallet_merged + arqma-wallet-flutter-ffi.dll (native wallet, no arqma-wallet-rpc).
# Prereqs: MSYS2 MINGW64 packages per .github/workflows/tauri-app.yml (Windows / MSYS2 job), rustup target x86_64-pc-windows-gnu.
param(
    [string]$MsysRoot = "C:\msys64",
    [switch]$SkipArqmaCMake,
    [switch]$SkipFlutter
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$rustRoot = Join-Path $repoRoot "rust"
$tauriApp = Join-Path $rustRoot "tauri-app"

$env:Path = "$MsysRoot\mingw64\bin;$MsysRoot\usr\bin;" + $env:Path
$env:ARQMA_WALLET2_MSYS_ROOT = "$MsysRoot\mingw64"
$env:ARQMA_MINGW_BIN = "$MsysRoot\mingw64\bin"
$env:ARQMA_WALLET2_UPSTREAM_DIR = Join-Path $rustRoot "arqma-rpc-upstream"
if (-not $env:CARGO_PROFILE_RELEASE_LTO) { $env:CARGO_PROFILE_RELEASE_LTO = "thin" }

Push-Location $tauriApp
try {
    if (-not $SkipArqmaCMake) {
        npm run build:arqma:mingw
    }
} finally {
    Pop-Location
}

Push-Location $rustRoot
try {
    cargo build -p arqma-wallet-flutter-ffi --release --target x86_64-pc-windows-gnu
} finally {
    Pop-Location
}

$dll = Join-Path $rustRoot "target\x86_64-pc-windows-gnu\release\arqma_wallet_flutter_ffi.dll"
if (-not (Test-Path $dll)) { throw "Missing $dll" }
Write-Host "OK: $dll"

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
        & $flutterBat build windows --release
    } finally {
        Pop-Location
    }
}
