# Desktop Flutter GUI (Windows / Linux / macOS) always uses GitHub Latest ArqTras/FFI.
param(
    [string]$Repo = $(if ($env:ARQMA_FFI_REPO) { $env:ARQMA_FFI_REPO } else { "ArqTras/FFI" })
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Stamp = Join-Path $Root ".prebuilt\arqma-wallet-ffi\.desktop-active-version"

if ($env:ARQMA_FFI_DESKTOP_ALLOW_PIN -eq "1" -and $env:ARQMA_FFI_RELEASE_VERSION -and $env:ARQMA_FFI_RELEASE_VERSION -ne "latest") {
    Write-Host "[desktop-ffi] pinned ARQMA_FFI_RELEASE_VERSION=$($env:ARQMA_FFI_RELEASE_VERSION) (allow-pin mode)"
} else {
    if ($env:ARQMA_FFI_RELEASE_VERSION -and $env:ARQMA_FFI_RELEASE_VERSION -ne "latest") {
        Write-Host "[desktop-ffi] ignoring ARQMA_FFI_RELEASE_VERSION=$($env:ARQMA_FFI_RELEASE_VERSION) — desktop GUI uses Latest ArqTras/FFI" -ForegroundColor Yellow
    }
    $env:ARQMA_FFI_RELEASE_VERSION = "latest"
}

$Ver = & (Join-Path $PSScriptRoot "resolve-arqma-ffi-release-version.ps1") -Repo $Repo
if (Test-Path $Stamp) {
    $Prev = (Get-Content $Stamp -Raw).Trim()
    if ($Prev -ne $Ver) {
        $env:ARQMA_FFI_FORCE = "1"
        Write-Host "[desktop-ffi] Latest FFI release changed: $Prev -> $Ver (refreshing prebuilts)"
    }
}
New-Item -ItemType Directory -Force -Path (Split-Path $Stamp -Parent) | Out-Null
Set-Content -Path $Stamp -Value $Ver -NoNewline
Write-Output $Ver
