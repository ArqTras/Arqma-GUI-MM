# Build Flutter Windows release and zip the runner output under .\dist\.
# Self-contained portable layout: exe + data/flutter_assets + FFI DLL + MinGW deps (flat Release/) + bin\arqmad.exe + bin\arqma_flutter_solo_pool.exe.
#
#   cd flutter\arqma_wallet_gui
#   .\tool\package_flutter_release.ps1
#   .\tool\package_flutter_release.ps1 -BuildNativeWalletFfi   # upstream MinGW + FFI DLL, then Flutter
#   .\tool\package_flutter_release.ps1 -BuildInstaller        # optional Inno Setup (same naming as CI)
#
# Recommended prep (repo root): place arqmad in .\bin, then this script runs build\copy-to-tauri-bins.js so
# rust\tauri-app\src-tauri\bin\ is populated before bundling.

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
    $js = Join-Path $RepoRoot "build\copy-to-tauri-bins.js"
    if ($SkipCopyToTauriBins) { return }
    if (-not (Test-Path $js)) { return }
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        Write-Warning "Node.js not on PATH; skipped build/copy-to-tauri-bins.js (place arqmad manually under rust\tauri-app\src-tauri\bin\)."
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
    $srcDir = Join-Path $RepoRoot "rust\tauri-app\src-tauri\bin"
    $dstDir = Join-Path $ReleaseDir "bin"
    if (-not (Test-Path $srcDir)) {
        Write-Warning "Missing $srcDir - no bundled daemons to copy (see rust/tauri-app/src-tauri/bin/README.txt)."
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
        Write-Warning "No arqmad.exe (or solo pool) in $srcDir - copy from repo .\bin via build/copy-to-tauri-bins.js or build CI download."
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

$soloBin = Join-Path $repoRoot "rust\tauri-app\src-tauri\bin\arqma_flutter_solo_pool.exe"
if ($BuildNativeWalletFfi) {
    $ffiPs1 = Join-Path $repoRoot "rust\tool\build_native_wallet_flutter_ffi_windows.ps1"
    if (-not (Test-Path $ffiPs1)) { Write-Error "Missing $ffiPs1" }
    & $ffiPs1 -MsysRoot $MsysRoot -SkipFlutter
} elseif ($BuildSoloPool -or -not (Test-Path $soloBin)) {
    $soloPs1 = Join-Path $repoRoot "rust\tool\build_flutter_solo_pool.ps1"
    if (-not (Test-Path $soloPs1)) { Write-Error "Missing $soloPs1" }
    & $soloPs1 -MsysRoot $MsysRoot
} elseif (-not (Test-Path $rustDllGnu) -and -not (Test-Path $rustDllMsvc)) {
    Write-Warning (
        "Native wallet FFI (arqma_wallet_flutter_ffi.dll) not found under rust/target. " +
        "Build: rust\tool\build_native_wallet_flutter_ffi_windows.ps1 -SkipFlutter " +
        "or re-run with -BuildNativeWalletFfi."
    )
}

$versionLine = (Select-String -Path "pubspec.yaml" -Pattern "^\s*version:\s*(\S+)" | Select-Object -First 1).Matches.Groups[1].Value
if (-not $versionLine) { $versionLine = "0.0.0" }
# Release artifact names use semver only (same as Git tag, e.g. 5.1.0+1 -> 5.1.0).
$versionSafe = $versionLine -replace "\+.*", ""

$dist = Join-Path $GuiRoot "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

Copy-RepoRootDaemonToTauriBin -RepoRoot $repoRoot

$flutterBat = Resolve-FlutterBat
& $flutterBat build windows --release

$releaseDir = Join-Path $GuiRoot "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
    Write-Error "Missing $releaseDir after build"
}

Copy-RepoRootDaemonToTauriBin -RepoRoot $repoRoot
Copy-TauriBinIntoRelease -RepoRoot $repoRoot -ReleaseDir $releaseDir

# MinGW-built FFI: compiler runtime + Boost/OpenSSL/sodium/unbound/ICU DLLs next to Arqma-Wallet.exe (Win32 126 if missing).
# Same globs as windows/cmake/install_arqma_wallet_ffi.cmake.in — flat Release layout (not Release\lib).
$mingwBin = Join-Path $MsysRoot "mingw64\bin"
$copiedDeps = 0
if (Test-Path $mingwBin) {
    foreach ($n in @("libgcc_s_seh-1.dll", "libstdc++-6.dll", "libwinpthread-1.dll")) {
        $s = Join-Path $mingwBin $n
        if (Test-Path $s) {
            Copy-Item -Force $s $releaseDir
            Write-Host "Copied MinGW runtime: $n -> $releaseDir"
            $copiedDeps++
        }
    }
    $globs = @(
        "libboost_*.dll","libcrypto*.dll","libssl*.dll","libsodium*.dll","libhidapi*.dll",
        "libunbound*.dll","libicu*.dll","libldns*.dll","libevent*.dll","libnghttp*.dll",
        "libcares*.dll","libexpat*.dll","libsqlite3*.dll","libgmp*.dll",
        "libzstd*.dll","zlib1.dll","libbz2*.dll","liblzma*.dll","libxml2*.dll","libiconv*.dll",
        "libzmq*.dll","liblmdb*.dll","libunwind*.dll","libreadline*.dll","libhistory*.dll",
        "libtermcap*.dll","libncurses*.dll","libncursesw*.dll","libintl*.dll","libffi*.dll",
        "libssp*.dll","liblz4*.dll","libbrotli*.dll","libdeflate*.dll","libatomic*.dll"
    )
    foreach ($pat in $globs) {
        Get-ChildItem -Path "$mingwBin\$pat" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '^libboost_python' -and $_.Name -notmatch '^libboost_numpy' } |
            ForEach-Object {
                Copy-Item -Force $_.FullName $releaseDir
                $script:copiedDeps++
            }
    }
    Write-Host "MinGW dependency DLLs synced: $copiedDeps file(s) -> $releaseDir"
} else {
    Write-Warning "MinGW bin not found at $mingwBin - wallet FFI will not load unless you copy MinGW dependency DLLs into Release (next to the exe)."
}

foreach ($merged in @(
        (Join-Path $repoRoot "rust\arqma-rpc-upstream\build-mingw\src\wallet\libwallet_merged.a"),
        (Join-Path $repoRoot "arqma-rpc-upstream\build-mingw\src\wallet\libwallet_merged.a")
    )) {
    if (Test-Path $merged) {
        Copy-Item -Force $merged $releaseDir
        Write-Host "Copied libwallet_merged.a -> $releaseDir"
        break
    }
}

if (-not $SkipBundleVerify) {
    & (Join-Path $PSScriptRoot "verify_windows_bundle.ps1") -ReleaseDir $releaseDir -FailIfNoArqmad -FailIfNoSoloPool
}

$zipName = "Arqma-Wallet-Flutter-$versionSafe-windows-x64.zip"
$zipPath = Join-Path $dist $zipName
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $zipPath -Force
Write-Host "Packaged: $zipPath"

if ($BuildInstaller) {
    $iss = Join-Path $repoRoot "build\ci\flutter-windows-installer.iss"
    if (-not (Test-Path $iss)) { throw "Missing $iss" }
    $verForInno = $versionLine -replace '\+.*', ''
    $isccCandidates = @(
        $env:INNO_ISCC
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe")
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
    ) | Where-Object { $_ -and (Test-Path $_) }
    $iscc = $isccCandidates | Select-Object -First 1
    if (-not $iscc) {
        Write-Warning "Inno Setup not found (set INNO_ISCC to ISCC.exe, or install Inno Setup 6). Omit -BuildInstaller for zip-only."
    } else {
        Push-Location $repoRoot
        try {
            & $iscc $iss "/DMyAppVersion=$verForInno" "/DVersionSafe=$versionSafe" "/DSrcRelease=$releaseDir"
            $setupOut = Join-Path $repoRoot "Arqma-Wallet-Flutter-${versionSafe}-windows-x64-Setup.exe"
            if (Test-Path $setupOut) {
                $setupDst = Join-Path $dist (Split-Path -Leaf $setupOut)
                Copy-Item -Force $setupOut $setupDst
                Write-Host "Installer: $setupDst"
            } else {
                Write-Warning "Expected Setup output next to repo root: $setupOut"
            }
        } finally {
            Pop-Location
        }
    }
}
