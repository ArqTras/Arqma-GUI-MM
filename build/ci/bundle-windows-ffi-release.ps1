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
    param([string]$DestDir, [string]$MingwBin, [switch]$RequireRuntime)
    foreach ($n in @("libgcc_s_seh-1.dll", "libstdc++-6.dll", "libwinpthread-1.dll")) {
        $src = Join-Path $MingwBin $n
        if (-not (Test-Path $src)) {
            $msg = "missing MinGW runtime: $src"
            if ($RequireRuntime -or $env:CI -eq "true" -or $env:GITHUB_ACTIONS -eq "true") {
                throw $msg
            }
            Write-Warning $msg
            continue
        }
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

function Copy-FfiPeImports {
    param([string]$FfiDll, [string]$DestDir, [string]$MingwBin)
    $objdump = Join-Path $MingwBin "objdump.exe"
    if (-not (Test-Path $objdump)) {
        Write-Host "[bundle-windows-ffi] skip PE import scan (no objdump at $objdump)"
        return 0
    }
    $system = @(
        'kernel32.dll', 'kernelbase.dll', 'ntdll.dll', 'msvcrt.dll', 'advapi32.dll',
        'shell32.dll', 'ws2_32.dll', 'userenv.dll', 'mswsock.dll', 'bcryptprimitives.dll'
    )
    $count = 0
    $imports = & $objdump -p $FfiDll 2>$null |
        Select-String '^\s*DLL Name:' |
        ForEach-Object { ($_.Line -replace '^\s*DLL Name:\s*', '').Trim() }
    foreach ($name in ($imports | Select-Object -Unique)) {
        $lower = $name.ToLowerInvariant()
        if ($lower -eq 'arqma_wallet_flutter_ffi.dll') { continue }
        if ($lower -like 'api-ms-*') { continue }
        if ($system -contains $lower) { continue }
        $src = Join-Path $MingwBin $name
        if (-not (Test-Path $src)) {
            Write-Host "[bundle-windows-ffi] import $name not in $MingwBin"
            continue
        }
        Copy-Item -Force $src (Join-Path $DestDir $name)
        $count++
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

$requireRt = ($env:CI -eq "true") -or ($env:GITHUB_ACTIONS -eq "true")
$n = Copy-MingwDeps -DestDir $ReleaseDir -MingwBin $mingwBin -RequireRuntime:$requireRt
$nPe = Copy-FfiPeImports -FfiDll $FfiDllSource -DestDir $ReleaseDir -MingwBin $mingwBin
Write-Host "[bundle-windows-ffi] MinGW dependency DLLs: $n glob + $nPe import(s) -> $ReleaseDir"
if ($requireRt -and $n -lt 1 -and $nPe -lt 1) {
    throw "no MinGW dependency DLLs copied from $mingwBin (wallet FFI will not load)"
}

# Legacy loader fallback: mirror under Release/lib/ (same prebuilt as root).
$legacyLib = Join-Path $ReleaseDir "lib"
New-Item -Force -ItemType Directory -Path $legacyLib | Out-Null
Copy-Item -Force (Join-Path $ReleaseDir "arqma_wallet_flutter_ffi.dll") (Join-Path $legacyLib "arqma_wallet_flutter_ffi.dll")
$nLib = Copy-MingwDeps -DestDir $legacyLib -MingwBin $mingwBin -RequireRuntime:$requireRt
$nLibPe = Copy-FfiPeImports -FfiDll $FfiDllSource -DestDir $legacyLib -MingwBin $mingwBin
Write-Host "[bundle-windows-ffi] legacy lib/ mirror: $($nLib + $nLibPe + 1) file(s)"
