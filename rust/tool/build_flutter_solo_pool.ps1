# Build arqma_flutter_solo_pool.exe (MinGW) and install into rust/tauri-app/src-tauri/bin/.
# Prereqs: MSYS2 MINGW64, rustup target x86_64-pc-windows-gnu, wallet_merged (npm run build:arqma:mingw).
param(
    [string]$MsysRoot = "C:\msys64",
    [switch]$SkipArqmaCMake
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$rustRoot = Join-Path $repoRoot "rust"
$tauriBin = Join-Path $rustRoot "tauri-app\src-tauri\bin"
New-Item -ItemType Directory -Force -Path $tauriBin | Out-Null

$env:Path = "$MsysRoot\mingw64\bin;$MsysRoot\usr\bin;" + $env:Path
$env:ARQMA_WALLET2_MSYS_ROOT = "$MsysRoot\mingw64"
$env:ARQMA_MINGW_BIN = "$MsysRoot\mingw64\bin"
$env:ARQMA_WALLET2_UPSTREAM_DIR = Join-Path $rustRoot "arqma-rpc-upstream"
if (-not $env:CARGO_PROFILE_RELEASE_LTO) { $env:CARGO_PROFILE_RELEASE_LTO = "thin" }

if (-not $SkipArqmaCMake) {
    Push-Location (Join-Path $rustRoot "tauri-app")
    try {
        npm run build:arqma:mingw
        if ($LASTEXITCODE -ne 0) { throw "npm run build:arqma:mingw failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
}

Push-Location $rustRoot
try {
    cargo build -p arqma-wallet --release --bin arqma_flutter_solo_pool --target x86_64-pc-windows-gnu
    if ($LASTEXITCODE -ne 0) { throw "cargo build arqma_flutter_solo_pool failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

$candidates = @(
    (Join-Path $rustRoot "target\x86_64-pc-windows-gnu\release\arqma_flutter_solo_pool.exe"),
    (Join-Path $rustRoot "target\release\arqma_flutter_solo_pool.exe"),
    (Join-Path $rustRoot "tauri-app\src-tauri\target\release\arqma_flutter_solo_pool.exe")
)
$dest = Join-Path $tauriBin "arqma_flutter_solo_pool.exe"
$copied = $false
foreach ($src in $candidates) {
    if (Test-Path $src) {
        Copy-Item -Force $src $dest
        Write-Host "Installed arqma_flutter_solo_pool.exe <- $src"
        $copied = $true
        break
    }
}
if (-not $copied) {
    throw "arqma_flutter_solo_pool.exe not found after cargo build"
}
Write-Host "Solo pool ready in $tauriBin"
