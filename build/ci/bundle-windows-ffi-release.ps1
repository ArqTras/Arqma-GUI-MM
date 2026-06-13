# Copy prebuilt wallet FFI + MinGW runtime deps flat next to Arqma-Wallet.exe (Release/).
# Only copies the PE import closure for arqma_wallet_flutter_ffi.dll (not every libboost_*.dll
# from MSYS2 — extra Boost DLLs preloaded before wallet FFI caused Win32 error 1114).
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDir,
    [string]$MsysRoot = "",
    [string]$FfiDllSource = ""
)

$ErrorActionPreference = "Stop"
$ReleaseDir = (Resolve-Path $ReleaseDir).Path
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

$Script:SystemDll = @(
    'kernel32.dll', 'kernelbase.dll', 'ntdll.dll', 'msvcrt.dll', 'advapi32.dll',
    'shell32.dll', 'ws2_32.dll', 'userenv.dll', 'mswsock.dll', 'bcryptprimitives.dll'
)

function Get-PeImportNames {
    param([string]$DllPath, [string]$Objdump)
    if (-not (Test-Path $DllPath)) { return @() }
    & $Objdump -p $DllPath 2>$null |
        Select-String '^\s*DLL Name:' |
        ForEach-Object { ($_.Line -replace '^\s*DLL Name:\s*', '').Trim() } |
        Select-Object -Unique
}

function Copy-RuntimeTriple {
    param([string]$DestDir, [string]$MingwBin, [switch]$RequireRuntime)
    $n = 0
    foreach ($name in @('libgcc_s_seh-1.dll', 'libstdc++-6.dll', 'libwinpthread-1.dll')) {
        $src = Join-Path $MingwBin $name
        if (-not (Test-Path $src)) {
            $msg = "missing MinGW runtime: $src"
            if ($RequireRuntime -or $env:CI -eq 'true' -or $env:GITHUB_ACTIONS -eq 'true') {
                throw $msg
            }
            Write-Warning $msg
            continue
        }
        Copy-Item -Force $src (Join-Path $DestDir $name)
        $n++
    }
    return $n
}

function Copy-FfiPeImportClosure {
    param(
        [string]$RootDll,
        [string]$DestDir,
        [string]$MingwBin,
        [string]$Objdump,
        [int]$MaxDepth = 8
    )
    $queue = [System.Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([pscustomobject]@{ Path = $RootDll; Depth = 0 })
    $seen = @{}
    $copied = 0

    while ($queue.Count -gt 0) {
        $item = $queue.Dequeue()
        $current = [string]$item.Path
        $depth = [int]$item.Depth
        $currentKey = $current.ToLowerInvariant()
        if ($seen.ContainsKey($currentKey)) { continue }
        $seen[$currentKey] = $true

        foreach ($name in (Get-PeImportNames -DllPath $current -Objdump $Objdump)) {
            $lower = $name.ToLowerInvariant()
            if ($lower -eq 'arqma_wallet_flutter_ffi.dll') { continue }
            if ($lower -like 'api-ms-*') { continue }
            if ($Script:SystemDll -contains $lower) { continue }

            $dest = Join-Path $DestDir $name
            if (-not (Test-Path $dest)) {
                $src = Join-Path $MingwBin $name
                if (-not (Test-Path $src)) {
                    Write-Host "[bundle-windows-ffi] missing import $name for $(Split-Path -Leaf $current)"
                    continue
                }
                Copy-Item -Force $src $dest
                $copied++
            }

            $destKey = $dest.ToLowerInvariant()
            if ($seen.ContainsKey($destKey)) { continue }
            if ($copied -gt 512) { throw 'PE import closure too large — aborting' }
            if ($depth -lt $MaxDepth) {
                $queue.Enqueue([pscustomobject]@{ Path = $dest; Depth = ($depth + 1) })
            }
        }
    }
    return $copied
}

function Resolve-MingwBin {
    param([string]$MsysRoot)
    if ($MsysRoot) {
        $root = $MsysRoot.TrimEnd('\', '/')
        if ($root -match 'mingw64\\?bin$') { return $root }
        if (Test-Path (Join-Path $root 'bin')) { return (Join-Path $root 'bin') }
        if (Test-Path (Join-Path $root 'mingw64\bin')) { return (Join-Path $root 'mingw64\bin') }
    }
    if ($env:ARQMA_WALLET2_MSYS_ROOT) {
        $mb = Join-Path $env:ARQMA_WALLET2_MSYS_ROOT.TrimEnd('\', '/') 'bin'
        if (Test-Path $mb) { return $mb }
    }
    if (Test-Path 'C:\msys64\mingw64\bin') { return 'C:\msys64\mingw64\bin' }
    return ''
}

function Sync-FfiLayout {
    param(
        [string]$DestDir,
        [string]$FfiDllSource,
        [string]$MingwBin,
        [string]$Objdump,
        [switch]$RequireRuntime
    )
    Copy-Item -Force $FfiDllSource (Join-Path $DestDir 'arqma_wallet_flutter_ffi.dll')
    $rt = Copy-RuntimeTriple -DestDir $DestDir -MingwBin $MingwBin -RequireRuntime:$RequireRuntime
    $closure = Copy-FfiPeImportClosure -RootDll $FfiDllSource -DestDir $DestDir -MingwBin $MingwBin -Objdump $Objdump
    return @{ runtime = $rt; closure = $closure }
}

function Clear-StaleWalletDeps {
    param([string]$Dir)
    if (-not (Test-Path $Dir)) { return }
    Get-ChildItem -Path $Dir -Filter '*.dll' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $n = $_.Name.ToLowerInvariant()
        if ($n -eq 'flutter_windows.dll') { return }
        if ($n -like 'local_auth*') { return }
        if ($n -like 'flutter_*') { return }
        Remove-Item -Force $_.FullName
    }
}

if (-not $FfiDllSource) {
    $FfiDllSource = Join-Path $RepoRoot 'rust\target\x86_64-pc-windows-gnu\release\arqma_wallet_flutter_ffi.dll'
}
if (-not (Test-Path $FfiDllSource)) {
    throw "missing FFI prebuilt (ArqTras/FFI): $FfiDllSource"
}

$mingwBin = Resolve-MingwBin -MsysRoot $MsysRoot
if (-not $mingwBin) {
    throw 'MinGW bin not found (pass -MsysRoot or set ARQMA_WALLET2_MSYS_ROOT)'
}
$objdump = Join-Path $mingwBin 'objdump.exe'
if (-not (Test-Path $objdump)) {
    throw "missing objdump: $objdump"
}

Write-Host "[bundle-windows-ffi] FFI <- $FfiDllSource -> $ReleaseDir"
Clear-StaleWalletDeps -Dir $ReleaseDir
$legacyLib = Join-Path $ReleaseDir 'lib'
Clear-StaleWalletDeps -Dir $legacyLib

$requireRt = ($env:CI -eq 'true') -or ($env:GITHUB_ACTIONS -eq 'true')
$stats = Sync-FfiLayout -DestDir $ReleaseDir -FfiDllSource $FfiDllSource -MingwBin $mingwBin -Objdump $objdump -RequireRuntime:$requireRt
Write-Host "[bundle-windows-ffi] runtime=$($stats.runtime) import-closure=$($stats.closure) -> $ReleaseDir"
if ($requireRt -and $stats.runtime -lt 3) {
    throw 'MinGW runtime triple incomplete (libgcc/libstdc++/libwinpthread)'
}
if ($requireRt -and $stats.closure -lt 5) {
    throw 'PE import closure too small — wallet FFI dependencies missing'
}

$legacyLib = Join-Path $ReleaseDir 'lib'
New-Item -Force -ItemType Directory -Path $legacyLib | Out-Null
$libStats = Sync-FfiLayout -DestDir $legacyLib -FfiDllSource $FfiDllSource -MingwBin $mingwBin -Objdump $objdump -RequireRuntime:$requireRt
Write-Host "[bundle-windows-ffi] legacy lib/ mirror runtime=$($libStats.runtime) closure=$($libStats.closure)"

foreach ($merged in @(
        (Join-Path $RepoRoot 'rust\arqma-rpc-upstream\build-mingw\src\wallet\libwallet_merged.a'),
        (Join-Path $RepoRoot 'arqma-rpc-upstream\build-mingw\src\wallet\libwallet_merged.a')
    )) {
    if (Test-Path $merged) {
        Copy-Item -Force $merged $ReleaseDir
        Write-Host "[bundle-windows-ffi] copied libwallet_merged.a (optional)"
        break
    }
}
