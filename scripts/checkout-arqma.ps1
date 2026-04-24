# Shallow clone of github.com/arqma/arqma into vendor/arqma (gitignored).
# After clone, build upstream per https://github.com/arqma/arqma — then set ARQMA_BUILD_DIR to build/release.
$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Dest = Join-Path $Root "vendor" "arqma"
if (Test-Path (Join-Path $Dest ".git")) {
  Write-Host "[checkout-arqma] vendor/arqma already exists — skipping."
  exit 0
}
$Parent = Split-Path -Parent $Dest
New-Item -ItemType Directory -Force -Path $Parent | Out-Null
git clone --depth 1 "https://github.com/arqma/arqma.git" $Dest
Write-Host "[checkout-arqma] cloned to $Dest"
Write-Host "Build (see upstream README), then e.g.: `$env:ARQMA_BUILD_DIR = Join-Path '$Dest' 'build' 'release'`"
