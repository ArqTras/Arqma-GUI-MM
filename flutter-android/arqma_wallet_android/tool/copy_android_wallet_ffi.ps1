# Copy libarqma_wallet_flutter_ffi.so into jniLibs (arm64-v8a / x86_64 / armeabi-v7a).
# Prefers GitHub Release prebuilts (.prebuilt/arqma-wallet-ffi) unless ARQMA_BUILD_FFI_FROM_SOURCE=1.
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$App = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Lib = "libarqma_wallet_flutter_ffi.so"
$Version = if ($env:ARQMA_FFI_RELEASE_VERSION) { $env:ARQMA_FFI_RELEASE_VERSION } else { "1.0.1" }
$PrebuiltRoot = Join-Path $Root ".prebuilt\arqma-wallet-ffi\$Version"
$CppShared = "libc++_shared.so"

function Get-NdkHostPrebuilt {
    if ($IsWindows -or $env:OS -match "Windows") { return "windows-x86_64" }
    if ($IsMacOS) {
        if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or (uname -m 2>$null) -eq "arm64") {
            return "darwin-arm64"
        }
        return "darwin-x86_64"
    }
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
    if (-not $ndk) {
        Write-Warning "Android NDK not found; skip $CppShared for $Abi (set ANDROID_NDK_HOME)"
        return $false
    }
    $hostPrebuilt = Get-NdkHostPrebuilt
    $src = Join-Path $ndk "toolchains\llvm\prebuilt\$hostPrebuilt\sysroot\usr\lib\$NdkTriple\$CppShared"
    if (-not (Test-Path $src)) {
        Write-Warning "Missing NDK runtime: $src"
        return $false
    }
    $destDir = Join-Path $App "android\app\src\main\jniLibs\$Abi"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item -Force $src (Join-Path $destDir $CppShared)
    Write-Host "copied $Abi $CppShared <- $src"
    return $true
}

function Copy-PrebuiltJni {
    param([string]$Platform, [string]$Abi)
    $src = Join-Path $PrebuiltRoot "$Platform\jniLibs\$Abi\$Lib"
    if (-not (Test-Path $src)) { return $false }
    $destDir = Join-Path $App "android\app\src\main\jniLibs\$Abi"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item -Force $src (Join-Path $destDir $Lib)
    Write-Host "copied $Abi (release $Version) <- $src"
    return $true
}

function Ensure-ReleaseFetched {
    if ($env:ARQMA_BUILD_FFI_FROM_SOURCE -eq "1") { return }
    $need = @(
        @{ Platform = "android-arm64"; Abi = "arm64-v8a" },
        @{ Platform = "android-x86_64"; Abi = "x86_64" }
    )
    $missing = $false
    foreach ($n in $need) {
        $p = Join-Path $PrebuiltRoot "$($n.Platform)\jniLibs\$($n.Abi)\$Lib"
        if (-not (Test-Path $p)) { $missing = $true }
    }
    if ($missing) {
        $fetch = Join-Path $Root "build\ci\fetch-arqma-wallet-ffi-release.ps1"
        if (-not (Test-Path $fetch)) { throw "Missing $fetch" }
        & $fetch -Platforms android-arm64,android-x86_64
    }
}

$AndroidAbis = @(
    @{ Platform = "android-arm64"; Abi = "arm64-v8a"; NdkTriple = "aarch64-linux-android" },
    @{ Platform = "android-x86_64"; Abi = "x86_64"; NdkTriple = "x86_64-linux-android" }
)

if ($env:ARQMA_BUILD_FFI_FROM_SOURCE -ne "1") {
    Ensure-ReleaseFetched
    $Copied = $false
    foreach ($n in $AndroidAbis) {
        if (Copy-PrebuiltJni -Platform $n.Platform -Abi $n.Abi) {
            Copy-CppSharedForAbi -Abi $n.Abi -NdkTriple $n.NdkTriple | Out-Null
            $Copied = $true
        }
    }
    if ($Copied) { exit 0 }
    Write-Warning "Prebuilt FFI missing; falling back to rust/target"
}

$Pairs = @(
    @{ Triple = "aarch64-linux-android"; Abi = "arm64-v8a"; NdkTriple = "aarch64-linux-android" },
    @{ Triple = "x86_64-linux-android"; Abi = "x86_64"; NdkTriple = "x86_64-linux-android" },
    @{ Triple = "armv7-linux-androideabi"; Abi = "armeabi-v7a"; NdkTriple = "arm-linux-androideabi" }
)
$Copied = $false
foreach ($p in $Pairs) {
    $src = Join-Path $Root "rust\target\$($p.Triple)\release\$Lib"
    if (-not (Test-Path $src)) {
        Write-Host "skip $($p.Abi): missing $src"
        continue
    }
    $destDir = Join-Path $App "android\app\src\main\jniLibs\$($p.Abi)"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item -Force $src (Join-Path $destDir $Lib)
    Copy-CppSharedForAbi -Abi $p.Abi -NdkTriple $p.NdkTriple | Out-Null
    Write-Host "copied $($p.Abi) <- $src"
    $Copied = $true
}
if (-not $Copied) {
    Write-Error "No $Lib found. Run: .\build\ci\fetch-arqma-wallet-ffi-release.ps1 or set ARQMA_BUILD_FFI_FROM_SOURCE=1 and build rust FFI."
}
