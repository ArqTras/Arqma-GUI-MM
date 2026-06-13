# Download prebuilt arqma_flutter_solo_pool from GitHub Releases (ArqTras/FFI).
#
# Usage (repo root):
#   .\build\ci\fetch-arqma-wallet-solo-pool-release.ps1
#   .\build\ci\fetch-arqma-wallet-solo-pool-release.ps1 -Platforms windows-x86_64-gnu
#   $env:ARQMA_SOLO_POOL_RELEASE_VERSION = "1.0.4"
#   $env:ARQMA_SOLO_POOL_FORCE = "1"
#
# Layout: .prebuilt/arqma-wallet-solo-pool/<version>/<platform>/...
# Mirrors into build/flutter-desktop-bin/ and rust/target/... for copy_* scripts.

param(
    [string]$Version = $(if ($env:ARQMA_SOLO_POOL_RELEASE_VERSION) { $env:ARQMA_SOLO_POOL_RELEASE_VERSION }
        elseif ($env:ARQMA_FFI_RELEASE_VERSION) { $env:ARQMA_FFI_RELEASE_VERSION }
        else { "latest" }),
    [string]$Repo = $(if ($env:ARQMA_FFI_REPO) { $env:ARQMA_FFI_REPO } else { "ArqTras/FFI" }),
    [string[]]$Platforms = @("windows-x86_64-gnu"),
    [switch]$SkipTauriBinMirror,
    [switch]$SkipRustTargetMirror,
    [switch]$AllowMiss
)

$ErrorActionPreference = "Stop"
if ($Platforms.Count -eq 1 -and $Platforms[0] -match ",") {
    $Platforms = $Platforms[0] -split "," | ForEach-Object { $_.Trim() }
}
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $Version -or $Version -eq "latest") {
    if ($env:ARQMA_SOLO_POOL_RELEASE_VERSION -and $env:ARQMA_SOLO_POOL_RELEASE_VERSION -ne "latest") {
        $Version = $env:ARQMA_SOLO_POOL_RELEASE_VERSION
    } else {
        $Version = & (Join-Path $PSScriptRoot "resolve-arqma-ffi-release-version.ps1") -Repo $Repo
    }
}
Write-Host "[fetch-solo-pool] ArqTras/FFI release $Version ($Repo)"
$CacheRoot = Join-Path $Root ".prebuilt\arqma-wallet-solo-pool"
$VerDir = Join-Path $CacheRoot $Version
New-Item -ItemType Directory -Force -Path $VerDir | Out-Null

$BaseUrl = "https://github.com/$Repo/releases/download/$Version"
$Force = ($env:ARQMA_SOLO_POOL_FORCE -eq "1")

function Get-SoloPoolBinaryName {
    param([string]$Platform)
    if ($Platform -eq "windows-x86_64-gnu") { return "arqma_flutter_solo_pool.exe" }
    return "arqma_flutter_solo_pool"
}

function Flatten-Extracted {
    param([string]$Dest, [string]$Platform)
    foreach ($name in @($Platform, "solo-pool-$Platform")) {
        $inner = Join-Path $Dest $name
        if (Test-Path $inner) {
            Get-ChildItem -Path $inner -Force | ForEach-Object {
                Move-Item -Force $_.FullName $Dest
            }
            Remove-Item -Recurse -Force $inner -ErrorAction SilentlyContinue
        }
    }
}

function Find-SoloPoolBinary {
    param([string]$Dir, [string]$Platform)
    $name = Get-SoloPoolBinaryName -Platform $Platform
    $direct = Join-Path $Dir $name
    if (Test-Path $direct) { return $direct }
    return (Get-ChildItem -Path $Dir -Recurse -Filter $name -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}

function Ensure-Platform {
    param([string]$Platform)
    $dest = Join-Path $VerDir $Platform
    $stamp = Join-Path $dest ".extracted"
    if ((Test-Path $stamp) -and -not $Force) {
        Write-Host "[fetch-solo-pool] $Platform already at $dest"
        return $dest
    }
    $zipName = "arqma-wallet-solo-pool-${Platform}-${Version}.zip"
    $url = "$BaseUrl/$zipName"
    $tmpZip = Join-Path $env:TEMP $zipName
    Write-Host "[fetch-solo-pool] downloading $url"
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing
    } catch {
        Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue
        if ($AllowMiss) {
            Write-Warning "[fetch-solo-pool] miss: $url"
            return $null
        }
        throw "Failed to download $url — tag $Version on $Repo must include $zipName, or set ARQMA_SOLO_POOL_BUILD_FROM_SOURCE=1"
    }
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Expand-Archive -Force $tmpZip $dest
    Flatten-Extracted -Dest $dest -Platform $Platform
    $bin = Find-SoloPoolBinary -Dir $dest -Platform $Platform
    if (-not $bin) {
        Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue
        throw "solo pool binary missing under $dest after extract"
    }
    New-Item -ItemType File -Force -Path $stamp | Out-Null
    Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue
    Write-Host "[fetch-solo-pool] extracted -> $dest ($bin)"
    return $dest
}

function Mirror-TauriBin {
    param([string]$Platform, [string]$Dir)
    $src = Find-SoloPoolBinary -Dir $Dir -Platform $Platform
    if (-not $src) { return }
    $tauriBin = Join-Path $Root "build\flutter-desktop-bin"
    New-Item -ItemType Directory -Force -Path $tauriBin | Out-Null
    $name = Split-Path $src -Leaf
    Copy-Item -Force $src (Join-Path $tauriBin $name)
    Write-Host "[fetch-solo-pool] build/flutter-desktop-bin/ <- $src"
}

function Mirror-RustTargets {
    param([string]$Platform, [string]$Dir)
    $src = Find-SoloPoolBinary -Dir $Dir -Platform $Platform
    if (-not $src) { return }
    $name = Split-Path $src -Leaf
    switch ($Platform) {
        "windows-x86_64-gnu" {
            $out = Join-Path $Root "rust\target\x86_64-pc-windows-gnu\release"
            New-Item -ItemType Directory -Force -Path $out | Out-Null
            Copy-Item -Force $src (Join-Path $out $name)
            Write-Host "[fetch-solo-pool] rust target <- $src"
        }
        { $_ -in @("linux-x86_64", "macos-arm64", "macos-x86_64") } {
            $out = Join-Path $Root "rust\target\release"
            New-Item -ItemType Directory -Force -Path $out | Out-Null
            Copy-Item -Force $src (Join-Path $out $name)
            Write-Host "[fetch-solo-pool] rust target <- $src"
        }
    }
}

$fetched = 0
foreach ($p in $Platforms) {
    $dir = Ensure-Platform -Platform $p
    if (-not $dir) { continue }
    if (-not $SkipTauriBinMirror) { Mirror-TauriBin -Platform $p -Dir $dir }
    if (-not $SkipRustTargetMirror) { Mirror-RustTargets -Platform $p -Dir $dir }
    $fetched++
}

if ($fetched -eq 0 -and $AllowMiss) {
    Write-Error "[fetch-solo-pool] no platform fetched (AllowMiss)"
}

Write-Host "[fetch-solo-pool] done (version=$Version, cache=$VerDir)"
