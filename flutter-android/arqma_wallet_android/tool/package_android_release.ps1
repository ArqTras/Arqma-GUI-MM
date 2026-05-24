# Build release APK for Arqma Wallet Android.
$ErrorActionPreference = "Stop"
$App = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Root = (Resolve-Path (Join-Path $App "..\..")).Path
Set-Location $App

if ($env:ARQMA_SKIP_ANDROID_FFI_COPY -ne "1") {
  & (Join-Path $App "tool\copy_android_wallet_ffi.ps1")
}

& "$env:FLUTTER_ROOT\bin\flutter.bat" pub get
if (-not $?) {
  $flutter = "C:\Users\Arek\flutter-sdk\flutter\bin\flutter.bat"
  if (Test-Path $flutter) { & $flutter pub get } else { throw "flutter not in PATH" }
}
& flutter build apk --release
$out = Join-Path $App "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $out) {
  $dist = Join-Path $App "dist"
  New-Item -ItemType Directory -Force -Path $dist | Out-Null
  $name = "arqma-wallet-android-{0:yyyyMMdd}.apk" -f (Get-Date).ToUniversalTime()
  Copy-Item -Force $out (Join-Path $dist $name)
  Write-Host "APK: $dist"
}
