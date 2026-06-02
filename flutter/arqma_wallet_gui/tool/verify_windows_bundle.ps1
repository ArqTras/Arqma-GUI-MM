# Verify Flutter Windows Release folder is runnable standalone (exe, engine, FFI, assets, arqmad, solo pool).
# Usage: .\tool\verify_windows_bundle.ps1 [-ReleaseDir path] [-FailIfNoArqmad] [-FailIfNoSoloPool]
param(
    [string]$ReleaseDir = "",
    [switch]$FailIfNoArqmad,
    [switch]$FailIfNoSoloPool
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
        "libgcc_s_seh-1.dll",
        "libstdc++-6.dll",
        "libwinpthread-1.dll",
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

$soloPool = Join-Path $ReleaseDir "bin\arqma_flutter_solo_pool.exe"
if (-not (Test-Path $soloPool)) {
    $msg = "bundle verify: missing bin\arqma_flutter_solo_pool.exe (build: rust\tool\build_flutter_solo_pool.ps1)"
    if ($FailIfNoSoloPool) {
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
