# Build Flutter Windows release and zip the runner output under .\dist\.
# Run from flutter\arqma_wallet_gui (or pass no args; script cds to its parent).
#
#   cd flutter\arqma_wallet_gui
#   .\tool\package_flutter_release.ps1
#   .\tool\package_flutter_release.ps1 -BuildNativeWalletFfi   # upstream MinGW + FFI DLL, then Flutter

param(
    [switch]$BuildNativeWalletFfi,
    [string]$MsysRoot = "C:\msys64"
)

function Resolve-FlutterBat {
    foreach ($c in @(
            "$env:LOCALAPPDATA\puro\envs\stable\flutter\bin\flutter.bat",
            "$env:USERPROFILE\flutter-sdk\flutter\bin\flutter.bat",
            "$env:USERPROFILE\development\flutter\bin\flutter.bat",
            "C:\src\flutter\bin\flutter.bat"
        )) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    $cmd = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    "flutter"
}

$ErrorActionPreference = "Stop"
$GuiRoot = Split-Path -Parent $PSScriptRoot
Set-Location $GuiRoot

if (-not (Test-Path "pubspec.yaml")) {
    Write-Error "pubspec.yaml not found; run from flutter/arqma_wallet_gui"
}

$repoRoot = Split-Path (Split-Path $GuiRoot -Parent) -Parent
$rustDllGnu = Join-Path $repoRoot "rust\target\x86_64-pc-windows-gnu\release\arqma_wallet_flutter_ffi.dll"
$rustDllMsvc = Join-Path $repoRoot "rust\target\release\arqma_wallet_flutter_ffi.dll"

if ($BuildNativeWalletFfi) {
    $ffiPs1 = Join-Path $repoRoot "rust\tool\build_native_wallet_flutter_ffi_windows.ps1"
    if (-not (Test-Path $ffiPs1)) { Write-Error "Missing $ffiPs1" }
    & $ffiPs1 -MsysRoot $MsysRoot -SkipFlutter
} elseif (-not (Test-Path $rustDllGnu) -and -not (Test-Path $rustDllMsvc)) {
    Write-Warning (
        "Native wallet FFI (arqma_wallet_flutter_ffi.dll) not found under rust/target. " +
        "Build: rust\tool\build_native_wallet_flutter_ffi_windows.ps1 -SkipFlutter " +
        "or re-run with -BuildNativeWalletFfi."
    )
}

$versionLine = (Select-String -Path "pubspec.yaml" -Pattern "^\s*version:\s*(\S+)" | Select-Object -First 1).Matches.Groups[1].Value
if (-not $versionLine) { $versionLine = "0.0.0" }
$versionSafe = $versionLine -replace "\+", "-"

$dist = Join-Path $GuiRoot "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$flutterBat = Resolve-FlutterBat
& $flutterBat build windows --release

$releaseDir = Join-Path $GuiRoot "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
    Write-Error "Missing $releaseDir after build"
}

$zipName = "Arqma-Wallet-$versionSafe-windows-x64.zip"
$zipPath = Join-Path $dist $zipName
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $zipPath -Force
Write-Host "Packaged: $zipPath"
