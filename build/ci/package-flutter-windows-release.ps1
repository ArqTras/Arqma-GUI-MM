# Bundle Flutter Windows Release (FFI + daemons), verify, ZIP + optional Inno Setup.
# Run after: flutter build windows --release (from flutter/arqma_wallet_gui).
#
# CI:
#   pwsh -File build/ci/package-flutter-windows-release.ps1 `
#     -RepoRoot $env:GITHUB_WORKSPACE -VersionSafe 5.1.2 -MsysRoot C:\msys64\mingw64 `
#     -BuildInstaller -FailIfNoArqmad -FailIfNoSoloPool
#
# Local (zip only to dist/):
#   pwsh -File build/ci/package-flutter-windows-release.ps1 -RepoRoot (repo root) -ZipOutputDir dist -BuildInstaller

param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [string]$VersionSafe = "",
    [string]$MsysRoot = "",
    [string]$ZipOutputDir = "",
    [switch]$BuildInstaller,
    [switch]$FailIfNoArqmad,
    [switch]$FailIfNoSoloPool,
    [switch]$SkipDaemonSync
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path $RepoRoot).Path

$guiRoot = Join-Path $RepoRoot "flutter\arqma_wallet_gui"
$releaseDir = Join-Path $guiRoot "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
    throw "Missing Flutter Release folder (run flutter build windows --release first): $releaseDir"
}

if ([string]::IsNullOrWhiteSpace($VersionSafe)) {
    $pubspec = Join-Path $guiRoot "pubspec.yaml"
    $line = (Select-String -Path $pubspec -Pattern '^\s*version:\s*(\S+)' | Select-Object -First 1).Matches.Groups[1].Value
    if (-not $line) { $line = "0.0.0" }
    $VersionSafe = $line -replace '\+.*', ''
}

if ([string]::IsNullOrWhiteSpace($ZipOutputDir)) {
    $ZipOutputDir = $RepoRoot
} else {
    $ZipOutputDir = (Resolve-Path $ZipOutputDir -ErrorAction SilentlyContinue)?.Path
    if (-not $ZipOutputDir) {
        New-Item -ItemType Directory -Force -Path $ZipOutputDir | Out-Null
        $ZipOutputDir = (Resolve-Path $ZipOutputDir).Path
    }
}

$bundleFfi = Join-Path $RepoRoot "build\ci\bundle-windows-ffi-release.ps1"
if (-not (Test-Path $bundleFfi)) {
    throw "Missing $bundleFfi"
}
Write-Host "==> Bundle wallet FFI + MinGW import closure -> $releaseDir"
& $bundleFfi -ReleaseDir $releaseDir -MsysRoot $MsysRoot

if (-not $SkipDaemonSync) {
    $copyJs = Join-Path $RepoRoot "build\copy-to-flutter-desktop-bins.js"
    if (Test-Path $copyJs) {
        $node = Get-Command node -ErrorAction SilentlyContinue
        if ($node) {
            Push-Location $RepoRoot
            try {
                & node $copyJs
            } finally {
                Pop-Location
            }
        } else {
            Write-Warning "Node.js not on PATH; skipped $copyJs"
        }
    }
    $binDst = Join-Path $releaseDir "bin"
    New-Item -Force -ItemType Directory -Path $binDst | Out-Null
    $binSrc = Join-Path $RepoRoot "build\flutter-desktop-bin"
    foreach ($exe in @("arqmad.exe", "arqma_flutter_solo_pool.exe")) {
        $src = Join-Path $binSrc $exe
        if (Test-Path $src) {
            Copy-Item -Force $src (Join-Path $binDst $exe)
            Write-Host "Synced $exe -> $binDst"
        }
    }
}

$verifyBundle = Join-Path $guiRoot "tool\verify_windows_bundle.ps1"
if (-not (Test-Path $verifyBundle)) {
    throw "Missing $verifyBundle"
}
Write-Host "==> Verify Release folder"
$verifyArgs = @{
    ReleaseDir       = $releaseDir
    FailIfNoArqmad   = $FailIfNoArqmad
    FailIfNoSoloPool = $FailIfNoSoloPool
}
& $verifyBundle @verifyArgs

$zipName = "Arqma-Wallet-Flutter-${VersionSafe}-windows-x64.zip"
$zipPath = Join-Path $ZipOutputDir $zipName
if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
}
Write-Host "==> ZIP $zipPath"
Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $zipPath -Force
Get-Item $zipPath | Format-List Name, Length, LastWriteTime

$setupPath = ""
if ($BuildInstaller) {
    $iconSrc = Join-Path $guiRoot "windows\runner\resources\app_icon.ico"
    if (-not (Test-Path $iconSrc)) {
        throw "Missing Windows app icon for installer: $iconSrc"
    }
    Copy-Item -Force $iconSrc (Join-Path $releaseDir "app_icon.ico")
    if ($env:CI -eq 'true' -or $env:GITHUB_ACTIONS -eq 'true') {
        choco install innosetup -y --no-progress | Out-Null
    }
    $iss = Join-Path $RepoRoot "build\ci\flutter-windows-installer.iss"
    if (-not (Test-Path $iss)) {
        throw "Missing $iss"
    }
    $isccCandidates = @(
        $env:INNO_ISCC
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe")
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
    ) | Where-Object { $_ -and (Test-Path $_) }
    $iscc = $isccCandidates | Select-Object -First 1
    if (-not $iscc) {
        throw "Inno Setup ISCC.exe not found (install Inno Setup 6 or set INNO_ISCC)"
    }
    $releaseAbs = (Resolve-Path $releaseDir).Path
    Write-Host "==> Inno Setup -> $RepoRoot"
    & $iscc $iss "/DMyAppVersion=$VersionSafe" "/DVersionSafe=$VersionSafe" "/DSrcRelease=$releaseAbs"
    $setupPath = Join-Path $RepoRoot "Arqma-Wallet-Flutter-${VersionSafe}-windows-x64-Setup.exe"
    if (-not (Test-Path $setupPath)) {
        throw "Missing installer output: $setupPath"
    }
    Get-Item $setupPath | Format-List Name, Length, LastWriteTime
}

$verifyArtifacts = Join-Path $RepoRoot "build\ci\verify-windows-release-artifacts.ps1"
if (-not (Test-Path $verifyArtifacts)) {
    throw "Missing $verifyArtifacts"
}
Write-Host "==> Verify ZIP (+ Setup when built)"
$artifactArgs = @{ ZipPath = $zipPath }
if ($setupPath) {
    $artifactArgs.SetupPath = $setupPath
}
& $verifyArtifacts @artifactArgs

Write-Host "==> Windows release packaging complete"
Write-Host "    ZIP: $zipPath"
if ($setupPath) {
    Write-Host "    Setup: $setupPath"
}
