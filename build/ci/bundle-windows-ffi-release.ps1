# Copy prebuilt wallet FFI + MinGW runtime deps flat next to Arqma-Wallet.exe (Release/).
# Matches install_arqma_wallet_ffi.cmake.in and tool/package_flutter_release.ps1.
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDir,
    [string]$MsysRoot = "",
    [string]$FfiDllSource = ""
)

$ErrorActionPreference = "Stop"
$ReleaseDir = (Resolve-Path $ReleaseDir).Path
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

function Copy-MingwDeps {
    param([string]$DestDir, [string]$MingwBin)
    foreach ($n in @("libgcc_s_seh-1.dll", "libstdc++-6.dll", "libwinpthread-1.dll")) {
        $src = Join-Path $MingwBin $n
        if (-not (Test-Path $src)) { Write-Warning "missing MinGW runtime: $src"; continue }
        Copy-Item -Force $src $DestDir
    }
    $patterns = @(
        "libboost_*.dll", "libcrypto*.dll", "libssl*.dll", "libsodium*.dll", "libhidapi*.dll",
        "libunbound*.dll", "libicu*.dll", "libldns*.dll", "libevent*.dll", "libnghttp*.dll",
        "libcares*.dll", "libexpat*.dll", "libsqlite3*.dll", "libgmp*.dll",
        "libzstd*.dll", "zlib1.dll", "libbz2*.dll", "liblzma*.dll", "libxml2*.dll", "libiconv*.dll",
        "libzmq*.dll", "liblmdb*.dll", "libunwind*.dll", "libreadline*.dll", "libhistory*.dll",
        "libtermcap*.dll", "libncurses*.dll", "libncursesw*.dll", "libintl*.dll", "libffi*.dll",
        "libssp*.dll", "liblz4*.dll", "libbrotli*.dll", "libdeflate*.dll", "libatomic*.dll"
    )
    $count = 0
    foreach ($pat in $patterns) {
        Get-ChildItem -Path "$MingwBin\$pat" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '^libboost_python' -and $_.Name -notmatch '^libboost_numpy' } |
            ForEach-Object {
                Copy-Item -Force $_.FullName $DestDir
                $count++
            }
    }
    return $count
}

if (-not $FfiDllSource) {
    $FfiDllSource = Join-Path $RepoRoot "rust\target\x86_64-pc-windows-gnu\release\arqma_wallet_flutter_ffi.dll"
}
if (-not (Test-Path $FfiDllSource)) {
    throw "missing FFI prebuilt (ArqTras/FFI): $FfiDllSource"
}
Copy-Item -Force $FfiDllSource (Join-Path $ReleaseDir "arqma_wallet_flutter_ffi.dll")
Write-Host "[bundle-windows-ffi] FFI <- $FfiDllSource -> $ReleaseDir"

$mingwBin = ""
if ($MsysRoot) {
    $root = $MsysRoot.TrimEnd('\', '/')
    if ($root -match 'mingw64\\?bin$') { $mingwBin = $root }
    elseif (Test-Path (Join-Path $root "bin")) { $mingwBin = Join-Path $root "bin" }
    elseif (Test-Path (Join-Path $root "mingw64\bin")) { $mingwBin = Join-Path $root "mingw64\bin" }
}
if (-not $mingwBin -and $env:ARQMA_WALLET2_MSYS_ROOT) {
    $mb = Join-Path $env:ARQMA_WALLET2_MSYS_ROOT.TrimEnd('\', '/') "bin"
    if (Test-Path $mb) { $mingwBin = $mb }
}
if (-not $mingwBin -and (Test-Path "C:\msys64\mingw64\bin")) {
    $mingwBin = "C:\msys64\mingw64\bin"
}
if (-not $mingwBin) {
    throw "MinGW bin not found (pass -MsysRoot or set ARQMA_WALLET2_MSYS_ROOT)"
}

$n = Copy-MingwDeps -DestDir $ReleaseDir -MingwBin $mingwBin
Write-Host "[bundle-windows-ffi] MinGW dependency DLLs: $n file(s) -> $ReleaseDir"

# Legacy loader fallback: mirror under Release/lib/ (same prebuilt as root).
$legacyLib = Join-Path $ReleaseDir "lib"
New-Item -Force -ItemType Directory -Path $legacyLib | Out-Null
Copy-Item -Force (Join-Path $ReleaseDir "arqma_wallet_flutter_ffi.dll") (Join-Path $legacyLib "arqma_wallet_flutter_ffi.dll")
$nLib = Copy-MingwDeps -DestDir $legacyLib -MingwBin $mingwBin
Write-Host "[bundle-windows-ffi] legacy lib/ mirror: $($nLib + 1) file(s)"
