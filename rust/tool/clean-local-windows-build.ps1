# Remove local Windows / MinGW / Flutter build outputs under this repo (does not delete sources or .git).
param(
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Remove-Tree([string]$path) {
    if (-not (Test-Path $path)) { return }
    if ($WhatIf) {
        Write-Host "[whatif] would remove $path"
        return
    }
    Remove-Item -Recurse -Force $path
    Write-Host "Removed $path"
}

Write-Host "Repo root: $repoRoot"

Remove-Tree (Join-Path $repoRoot "rust\target")
Remove-Tree (Join-Path $repoRoot "flutter\arqma_wallet_gui\build")
Remove-Tree (Join-Path $repoRoot "rust\arqma-rpc-upstream\build-mingw")
Remove-Tree (Join-Path $repoRoot "rust\arqma-rpc-upstream\build")
Remove-Tree (Join-Path $repoRoot "downloads\extract-ci-flutter-win")

Write-Host "Done. Re-run upstream CMake (build-arqma-mingw) and cargo/flutter builds."
