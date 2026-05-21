#!/usr/bin/env bash
# Generate iOS AppIcon.appiconset and Android mipmap launcher icons from the Arqma logo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/assets/images/arq_logo_with_padding.png}"
IOS_SET="$ROOT/ios/Runner/Assets.xcassets/AppIcon.appiconset"
LAUNCH_SET="$ROOT/ios/Runner/Assets.xcassets/LaunchImage.imageset"
ANDROID_RES="$ROOT/android/app/src/main/res"
BRANDING="$ROOT/assets/branding/app_icon.png"

if [[ ! -f "$SRC" ]]; then
  echo "Source image not found: $SRC" >&2
  exit 1
fi

resize() {
  local out="$1"
  local px="$2"
  mkdir -p "$(dirname "$out")"
  sips -z "$px" "$px" "$SRC" --out "$out" >/dev/null
}

echo "Source: $SRC"

# In-app / docs reference (512px)
resize "$BRANDING" 512

# iOS — filenames must match Contents.json
resize "$IOS_SET/Icon-App-20x20@1x.png" 20
resize "$IOS_SET/Icon-App-20x20@2x.png" 40
resize "$IOS_SET/Icon-App-20x20@3x.png" 60
resize "$IOS_SET/Icon-App-29x29@1x.png" 29
resize "$IOS_SET/Icon-App-29x29@2x.png" 58
resize "$IOS_SET/Icon-App-29x29@3x.png" 87
resize "$IOS_SET/Icon-App-40x40@1x.png" 40
resize "$IOS_SET/Icon-App-40x40@2x.png" 80
resize "$IOS_SET/Icon-App-40x40@3x.png" 120
resize "$IOS_SET/Icon-App-60x60@2x.png" 120
resize "$IOS_SET/Icon-App-60x60@3x.png" 180
resize "$IOS_SET/Icon-App-76x76@1x.png" 76
resize "$IOS_SET/Icon-App-76x76@2x.png" 152
resize "$IOS_SET/Icon-App-83.5x83.5@2x.png" 167
resize "$IOS_SET/Icon-App-1024x1024@1x.png" 1024

# iOS launch screen (storyboard LaunchImage — was 1×1 placeholder)
resize "$LAUNCH_SET/LaunchImage.png" 200
resize "$LAUNCH_SET/LaunchImage@2x.png" 400
resize "$LAUNCH_SET/LaunchImage@3x.png" 600

# Android launcher
resize "$ANDROID_RES/mipmap-mdpi/ic_launcher.png" 48
resize "$ANDROID_RES/mipmap-hdpi/ic_launcher.png" 72
resize "$ANDROID_RES/mipmap-xhdpi/ic_launcher.png" 96
resize "$ANDROID_RES/mipmap-xxhdpi/ic_launcher.png" 144
resize "$ANDROID_RES/mipmap-xxxhdpi/ic_launcher.png" 192

echo "Done: iOS AppIcon + LaunchImage + Android ic_launcher + $BRANDING"
