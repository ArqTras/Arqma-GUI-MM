#!/usr/bin/env bash
# Pack a Flutter Linux release bundle (directory with Arqma-Wallet + lib/ + data/) into a type-2 AppImage.
# Requires: curl, chmod, mktemp. Uses upstream appimagetool (extract-and-run, no FUSE on CI).
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="${1:?usage: $0 <path-to-flutter-linux-release-bundle> [output.AppImage]}"
OUT="${2:-$ROOT/Arqma-Wallet-Flutter-x86_64.AppImage}"
TOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
ICON="${ARQMA_FLUTTER_APPIMAGE_ICON:-$ROOT/rust/tauri-app/public/icon_512x512.png}"

test -x "$BUNDLE/Arqma-Wallet" || { echo "error: missing executable $BUNDLE/Arqma-Wallet" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL -o "$TMP/appimagetool" "$TOOL_URL"
chmod +x "$TMP/appimagetool"

APPDIR="$TMP/AppDir"
mkdir -p "$APPDIR"
cp -a "$BUNDLE"/. "$APPDIR/"

cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE" || exit 1
exec ./Arqma-Wallet "$@"
EOF
chmod +x "$APPDIR/AppRun"

cat > "$APPDIR/arqma-wallet.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Arqma Wallet
Comment=Arqma desktop wallet (Flutter)
Exec=Arqma-Wallet
Icon=arqma-wallet
Categories=Network;Finance;
Terminal=false
StartupWMClass=arqma_wallet
EOF

if [ -f "$ICON" ]; then
  cp -f "$ICON" "$APPDIR/arqma-wallet.png"
else
  echo "warning: icon not found at $ICON — AppImage may lack icon" >&2
fi

export ARCH=x86_64
export APPIMAGE_EXTRACT_AND_RUN=1
"$TMP/appimagetool" "$APPDIR" "$OUT"
echo "[flutter-linux-bundle-to-appimage] OK -> $OUT"
ls -la "$OUT"
