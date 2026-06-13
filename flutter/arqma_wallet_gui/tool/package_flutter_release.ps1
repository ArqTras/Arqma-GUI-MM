# Build Flutter Windows release and zip the runner output under .\dist\.
# Self-contained portable layout: exe + data/flutter_assets + FFI DLL + MinGW deps (flat Release/) + bin\arqmad.exe + bin\arqma_flutter_solo_pool.exe.
#
#   cd flutter\arqma_wallet_gui
#   .\tool\package_flutter_release.ps1
#   .\tool\package_flutter_release.ps1 -BuildNativeWalletFfi   # upstream MinGW + FFI DLL, then Flutter
#   .\tool\package_flutter_release.ps1 -BuildInstaller        # optional Inno Setup (same naming as CI)
#
# Recommended prep (repo root): place arqmad in .\bin, then this script runs build\copy-to-flutter-desktop-bins.js so
# build\flutter-desktop-bin\ is populated before bundling.

param(
    [switch]$BuildNativeWalletFfi,
    [switch]$BuildSoloPool,
    [string]$MsysRoot = "C:\msys64",
    [switch]$SkipCopyToTauriBins,
    [switch]$SkipBundleVerify,
    [switch]$BuildInstaller
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

function Copy-RepoRootDaemonToTauriBin {
    param([string]$RepoRoot)
    $js = Join-Path $RepoRoot "build\copy-to-flutter-desktop-bins.js"
    if ($SkipCopyToTauriBins) { return }
    if (-not (Test-Path $js)) { return }
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        Write-Warning "Node.js not on PATH; skipped build/copy-to-flutter-desktop-bins.js (place arqmad manually under build\flutter-desktop-bin\)."
        return
    }
    Push-Location $RepoRoot
    try {
        & node $js
    } finally {
        Pop-Location
    }
}

function Copy-TauriBinIntoRelease {
    param([string]$RepoRoot, [string]$ReleaseDir)
    $srcDir = Join-Path $RepoRoot "build\flutter-desktop-bin"
    $dstDir = Join-Path $ReleaseDir "bin"
    if (-not (Test-Path $srcDir)) {
        Write-Warning "Missing $srcDir - no bundled daemons to copy (see build/flutter-desktop-bin/README.txt)."
        return
    }
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    $n = 0
    foreach ($exe in @("arqmad.exe", "arqma_flutter_solo_pool.exe")) {
        $src = Join-Path $srcDir $exe
        if (Test-Path $src) {
            Copy-Item -Force $src $dstDir
            Write-Host "Bundled $exe -> $dstDir"
            $n++
        }
    }
    if ($n -eq 0) {
        Write-Warning "No arqmad.exe (or solo pool) in $srcDir - copy from repo .\bin via build/copy-to-flutter-desktop-bins.js or build CI download."
    }
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

$soloBin = Join-Path $repoRoot "build\flutter-desktop-bin\arqma_flutter_solo_pool.exe"
if ($BuildNativeWalletFfi) {
    $ffiPs1 = Join-Path $repoRoot "rust\tool\build_native_wallet_flutter_ffi_windows.ps1"
    if (-not (Test-Path $ffiPs1)) { Write-Error "Missing $ffiPs1" }
    & $ffiPs1 -MsysRoot $MsysRoot -SkipFlutter
} else {
    $fetchDesktop = Join-Path $repoRoot "build\ci\fetch-arqma-desktop-prebuilts.ps1"
    if (-not (Test-Path $fetchDesktop)) { Write-Error "Missing $fetchDesktop" }
    & $fetchDesktop -MsysRoot $MsysRoot
    if ($BuildSoloPool) {
        $fetchSolo = Join-Path $repoRoot "build\ci\fetch-or-build-solo-pool-desktop.ps1"
        & $fetchSolo -MsysRoot $MsysRoot
    }
}
if (-not $BuildNativeWalletFfi -and -not (Test-Path $rustDllGnu) -and -not (Test-Path $rustDllMsvc)) {
    Write-Warning (
        "Native wallet FFI (arqma_wallet_flutter_ffi.dll) not found under rust/target. " +
        "Build: rust\tool\build_native_wallet_flutter_ffi_windows.ps1 -SkipFlutter " +
        "or re-run with -BuildNativeWalletFfi."
    )
}

$versionLine = (Select-String -Path "pubspec.yaml" -Pattern "^\s*version:\s*(\S+)" | Select-Object -First 1).Matches.Groups[1].Value
if (-not $versionLine) { $versionLine = "0.0.0" }
# Release artifact names use semver only (same as Git tag, e.g. 5.1.1+1 -> 5.1.1).
$versionSafe = $versionLine -replace "\+.*", ""

$dist = Join-Path $GuiRoot "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

Copy-RepoRootDaemonToTauriBin -RepoRoot $repoRoot

$flutterBat = Resolve-FlutterBat
$env:ARQMA_WALLET2_MSYS_ROOT = Join-Path $MsysRoot "mingw64"
& $flutterBat build windows --release

$releaseDir = Join-Path $GuiRoot "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
    Write-Error "Missing $releaseDir after build"
}

$packageWin = Join-Path $repoRoot "build\ci\package-flutter-windows-release.ps1"
if (-not (Test-Path $packageWin)) {
    Write-Error "Missing $packageWin"
}

$packageArgs = @{
    RepoRoot         = $repoRoot
    VersionSafe      = $versionSafe
    MsysRoot         = (Join-Path $MsysRoot "mingw64")
    ZipOutputDir     = $dist
    FailIfNoArqmad   = $true
    FailIfNoSoloPool = $true
}
if ($BuildInstaller) {
    $packageArgs.BuildInstaller = $true
}
& $packageWin @packageArgs

if ($BuildInstaller) {
    $setupOut = Join-Path $repoRoot "Arqma-Wallet-Flutter-${versionSafe}-windows-x64-Setup.exe"
    if (Test-Path $setupOut) {
        $setupDst = Join-Path $dist (Split-Path -Leaf $setupOut)
        Copy-Item -Force $setupOut $setupDst
        Write-Host "Installer copy: $setupDst"
    }
}
