# Fetch GitHub Latest ArqTras/FFI wallet DLL + solo pool for desktop GUI dev/build.
$ErrorActionPreference = "Stop"
$GuiRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot = Split-Path (Split-Path $GuiRoot -Parent) -Parent
& (Join-Path $RepoRoot "build\ci\fetch-arqma-desktop-prebuilts.ps1")
