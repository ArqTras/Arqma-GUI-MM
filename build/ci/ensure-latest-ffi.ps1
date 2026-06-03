# All Flutter targets use GitHub Latest ArqTras/FFI (see ensure-latest-ffi.sh).
param(
    [string]$Repo = $(if ($env:ARQMA_FFI_REPO) { $env:ARQMA_FFI_REPO } else { "ArqTras/FFI" })
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Stamp = Join-Path $Root ".prebuilt\arqma-wallet-ffi\.active-latest-version"

$AllowPin = ($env:ARQMA_FFI_ALLOW_PIN -eq "1" -or $env:ARQMA_FFI_DESKTOP_ALLOW_PIN -eq "1")

if ($AllowPin -and $env:ARQMA_FFI_RELEASE_VERSION -and $env:ARQMA_FFI_RELEASE_VERSION -ne "latest") {
    Write-Host "[ffi] pinned ARQMA_FFI_RELEASE_VERSION=$($env:ARQMA_FFI_RELEASE_VERSION) (allow-pin mode)"
} else {
    if ($env:ARQMA_FFI_RELEASE_VERSION -and $env:ARQMA_FFI_RELEASE_VERSION -ne "latest") {
        Write-Host "[ffi] ignoring ARQMA_FFI_RELEASE_VERSION=$($env:ARQMA_FFI_RELEASE_VERSION) — project policy uses Latest ArqTras/FFI" -ForegroundColor Yellow
    }
    $env:ARQMA_FFI_RELEASE_VERSION = "latest"
}

$Ver = & (Join-Path $PSScriptRoot "resolve-arqma-ffi-release-version.ps1") -Repo $Repo
if (Test-Path $Stamp) {
    $Prev = (Get-Content $Stamp -Raw).Trim()
    if ($Prev -ne $Ver) {
        $env:ARQMA_FFI_FORCE = "1"
        Write-Host "[ffi] Latest release changed: $Prev -> $Ver (refreshing prebuilts)"
    }
}
New-Item -ItemType Directory -Force -Path (Split-Path $Stamp -Parent) | Out-Null
Set-Content -Path $Stamp -Value $Ver -NoNewline
Write-Output $Ver
