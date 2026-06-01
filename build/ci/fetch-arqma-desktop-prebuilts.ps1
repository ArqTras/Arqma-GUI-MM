# Fetch wallet FFI + solo pool for Flutter desktop (Latest ArqTras/FFI release).
param(
    [ValidateSet("mingw")]
    [string]$HostPlatform = "mingw"
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Platform = "windows-x86_64-gnu"
$Ver = & (Join-Path $PSScriptRoot "ensure-desktop-latest-ffi.ps1")
Write-Host "[desktop-prebuilts] ArqTras/FFI release $Ver ($Platform)"

& (Join-Path $PSScriptRoot "fetch-arqma-wallet-ffi-release.ps1") -Platforms $Platform
& (Join-Path $PSScriptRoot "fetch-arqma-wallet-solo-pool-release.ps1") -Platforms $Platform

Write-Host "[desktop-prebuilts] OK"
