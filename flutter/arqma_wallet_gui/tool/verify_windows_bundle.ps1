# Verify Flutter Windows Release folder is runnable standalone (exe, engine, FFI, assets, optional arqmad).
# Usage: .\tool\verify_windows_bundle.ps1 [-ReleaseDir path] [-FailIfNoArqmad]
param(
    [string]$ReleaseDir = "",
    [switch]$FailIfNoArqmad
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ReleaseDir)) {
    $gui = Split-Path -Parent $PSScriptRoot
    $ReleaseDir = Join-Path $gui "build\windows\x64\runner\Release"
}
if (-not (Test-Path $ReleaseDir)) {
    Write-Error "Release dir not found: $ReleaseDir"
}

$failed = $false
foreach ($rel in @(
        "Arqma-Wallet.exe",
        "arqma_wallet_flutter_ffi.dll",
        "flutter_windows.dll",
        "data\flutter_assets\AssetManifest.bin"
    )) {
    $p = Join-Path $ReleaseDir $rel
    if (-not (Test-Path $p)) {
        Write-Host "::error::bundle verify: missing $rel"
        $failed = $true
    }
}
$arqmad = Join-Path $ReleaseDir "bin\arqmad.exe"
if (-not (Test-Path $arqmad)) {
    $msg = "bundle verify: missing bin\arqmad.exe (set ARQMA_DAEMON or add daemon to bundle)"
    if ($FailIfNoArqmad) {
        Write-Host "::error::$msg"
        $failed = $true
    } else {
        Write-Host "::warning::$msg"
    }
}

if ($failed) {
    exit 1
}
Write-Host "bundle verify: OK - $ReleaseDir"
