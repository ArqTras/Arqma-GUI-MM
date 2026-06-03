# Back-compat wrapper — see ensure-latest-ffi.ps1 (all Flutter platforms).
param(
    [string]$Repo = $(if ($env:ARQMA_FFI_REPO) { $env:ARQMA_FFI_REPO } else { "ArqTras/FFI" })
)
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
& (Join-Path $PSScriptRoot "ensure-latest-ffi.ps1") -Repo $Repo
