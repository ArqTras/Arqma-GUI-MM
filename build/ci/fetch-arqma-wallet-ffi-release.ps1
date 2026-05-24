# Download prebuilt arqma-wallet-flutter-ffi from GitHub Releases (ArqTras/FFI).
# Default: tag 1.0.0 — https://github.com/ArqTras/FFI/releases/tag/1.0.0
#
# Usage (repo root):
#   .\build\ci\fetch-arqma-wallet-ffi-release.ps1
#   .\build\ci\fetch-arqma-wallet-ffi-release.ps1 -Platforms windows-x86_64-gnu,android-x86_64
#   $env:ARQMA_FFI_RELEASE_VERSION = "1.0.0"
#   $env:ARQMA_FFI_FORCE = "1"   # re-download
#
# Layout: .prebuilt/arqma-wallet-ffi/<version>/<platform>/...
# Also mirrors into rust/target/... for existing copy_* scripts.

param(
    [string]$Version = $(if ($env:ARQMA_FFI_RELEASE_VERSION) { $env:ARQMA_FFI_RELEASE_VERSION } else { "1.0.0" }),
    [string]$Repo = "ArqTras/FFI",
    [string[]]$Platforms = @(
        "windows-x86_64-gnu",
        "android-arm64",
        "android-x86_64"
    ),
    [switch]$SkipRustTargetMirror,
    [switch]$SkipJniLibsMirror
)

$ErrorActionPreference = "Stop"
if ($Platforms.Count -eq 1 -and $Platforms[0] -match ",") {
    $Platforms = $Platforms[0] -split "," | ForEach-Object { $_.Trim() }
}
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$CacheRoot = Join-Path $Root ".prebuilt\arqma-wallet-ffi"
$VerDir = Join-Path $CacheRoot $Version
New-Item -ItemType Directory -Force -Path $VerDir | Out-Null

$BaseUrl = "https://github.com/$Repo/releases/download/$Version"
$Force = ($env:ARQMA_FFI_FORCE -eq "1")

function Ensure-Platform {
    param([string]$Platform)
    $dest = Join-Path $VerDir $Platform
    $stamp = Join-Path $dest ".extracted"
    if ((Test-Path $stamp) -and -not $Force) {
        Write-Host "[fetch-ffi] $Platform already at $dest"
        return $dest
    }
    $zipName = "arqma-wallet-ffi-${Platform}-${Version}.zip"
    $url = "$BaseUrl/$zipName"
    $tmpZip = Join-Path $env:TEMP $zipName
    Write-Host "[fetch-ffi] downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Expand-Archive -Force $tmpZip $dest
    # Zip contains a single top-level folder named like the platform.
    $inner = Join-Path $dest $Platform
    if (Test-Path $inner) {
        Get-ChildItem -Path $inner -Force | ForEach-Object {
            Move-Item -Force $_.FullName $dest
        }
        Remove-Item -Recurse -Force $inner -ErrorAction SilentlyContinue
    }
    New-Item -ItemType File -Force -Path $stamp | Out-Null
    Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue
    Write-Host "[fetch-ffi] extracted -> $dest"
    return $dest
}

function Mirror-RustTargets {
    param([string]$Platform, [string]$Dir)
    $rust = Join-Path $Root "rust\target"
    switch ($Platform) {
        "windows-x86_64-gnu" {
            $dll = Join-Path $Dir "arqma_wallet_flutter_ffi.dll"
            if (-not (Test-Path $dll)) { throw "missing $dll" }
            $out = Join-Path $rust "x86_64-pc-windows-gnu\release"
            New-Item -ItemType Directory -Force -Path $out | Out-Null
            Copy-Item -Force $dll (Join-Path $out "arqma_wallet_flutter_ffi.dll")
            Write-Host "[fetch-ffi] rust target <- $dll"
        }
        "android-arm64" {
            $so = Join-Path $Dir "jniLibs\arm64-v8a\libarqma_wallet_flutter_ffi.so"
            if (-not (Test-Path $so)) { throw "missing $so" }
            $out = Join-Path $rust "aarch64-linux-android\release"
            New-Item -ItemType Directory -Force -Path $out | Out-Null
            Copy-Item -Force $so (Join-Path $out "libarqma_wallet_flutter_ffi.so")
            Write-Host "[fetch-ffi] rust target <- $so"
        }
        "android-x86_64" {
            $so = Join-Path $Dir "jniLibs\x86_64\libarqma_wallet_flutter_ffi.so"
            if (-not (Test-Path $so)) { throw "missing $so" }
            $out = Join-Path $rust "x86_64-linux-android\release"
            New-Item -ItemType Directory -Force -Path $out | Out-Null
            Copy-Item -Force $so (Join-Path $out "libarqma_wallet_flutter_ffi.so")
            Write-Host "[fetch-ffi] rust target <- $so"
        }
    }
}

function Get-NdkHostPrebuilt {
    if ($IsWindows -or $env:OS -match "Windows") { return "windows-x86_64" }
    if ($IsMacOS) { return "darwin-x86_64" }
    return "linux-x86_64"
}

function Resolve-NdkRoot {
    foreach ($c in @($env:ANDROID_NDK_HOME, $env:ANDROID_NDK_ROOT)) {
        if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
    }
    $sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT }
        elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME }
        else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
    $ndkDir = Join-Path $sdk "ndk"
    if (-not (Test-Path $ndkDir)) { return $null }
    return (Get-ChildItem -Path $ndkDir -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
}

function Copy-CppSharedForAbi {
    param([string]$Abi, [string]$NdkTriple)
    $ndk = Resolve-NdkRoot
    if (-not $ndk) { return }
    $src = Join-Path $ndk "toolchains\llvm\prebuilt\$(Get-NdkHostPrebuilt)\sysroot\usr\lib\$NdkTriple\libc++_shared.so"
    if (-not (Test-Path $src)) { return }
    $destDir = Join-Path $Root "flutter-android\arqma_wallet_android\android\app\src\main\jniLibs\$Abi"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item -Force $src (Join-Path $destDir "libc++_shared.so")
    Write-Host "[fetch-ffi] jniLibs/$Abi/libc++_shared.so <- $src"
}

function Mirror-JniLibs {
    param([string]$Platform, [string]$Dir)
    if ($Platform -notmatch "^android") { return }
    $app = Join-Path $Root "flutter-android\arqma_wallet_android"
    if (-not (Test-Path $app)) { return }
    $jniSrc = Join-Path $Dir "jniLibs"
    if (-not (Test-Path $jniSrc)) { return }
    $base = Join-Path $app "android\app\src\main\jniLibs"
    $ndkTriple = switch ($Platform) {
        "android-arm64" { "aarch64-linux-android" }
        "android-x86_64" { "x86_64-linux-android" }
        default { $null }
    }
    foreach ($abiDir in Get-ChildItem -Path $jniSrc -Directory) {
        $destAbi = Join-Path $base $abiDir.Name
        New-Item -ItemType Directory -Force -Path $destAbi | Out-Null
        Copy-Item -Force (Join-Path $abiDir.FullName "libarqma_wallet_flutter_ffi.so") (Join-Path $destAbi "libarqma_wallet_flutter_ffi.so")
        Write-Host "[fetch-ffi] jniLibs/$($abiDir.Name) -> $destAbi"
        if ($ndkTriple) { Copy-CppSharedForAbi -Abi $abiDir.Name -NdkTriple $ndkTriple }
    }
}

foreach ($p in $Platforms) {
    $dir = Ensure-Platform -Platform $p
    if (-not $SkipRustTargetMirror) { Mirror-RustTargets -Platform $p -Dir $dir }
    if (-not $SkipJniLibsMirror) { Mirror-JniLibs -Platform $p -Dir $dir }
}

Write-Host "[fetch-ffi] done (version=$Version, cache=$VerDir)"
