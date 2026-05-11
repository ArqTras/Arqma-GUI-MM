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

# MinGW-built FFI: compiler runtime + Boost/OpenSSL/sodium/unbound/ICU DLLs (otherwise Win32 error 126).
$mingwBin = Join-Path $MsysRoot "mingw64\bin"
if (Test-Path $mingwBin) {
    foreach ($n in @("libgcc_s_seh-1.dll", "libstdc++-6.dll", "libwinpthread-1.dll")) {
        $s = Join-Path $mingwBin $n
        if (Test-Path $s) {
            Copy-Item -Force $s $releaseDir
            Write-Host "Copied MinGW runtime: $n -> $releaseDir"
        }
    }
    # Match windows/cmake/install_arqma_wallet_ffi.cmake.in (MinGW deps for GNU FFI).
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
            ForEach-Object { Copy-Item -Force $_.FullName $releaseDir; Write-Host "Copied $($_.Name) -> $releaseDir" }
    }
} else {
    Write-Warning "MinGW bin not found at $mingwBin — wallet FFI will not load unless you copy MinGW dependency DLLs next to the exe."
}

$zipName = "Arqma-Wallet-Flutter-$versionSafe-windows-x64.zip"
$zipPath = Join-Path $dist $zipName
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $zipPath -Force
Write-Host "Packaged: $zipPath"
