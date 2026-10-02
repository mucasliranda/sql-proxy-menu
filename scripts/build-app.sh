#!/usr/bin/env bash
# Compila o app e monta o bundle em build/SQL Proxy Menu.app
#
# Assinatura:
#   - sem SIGN_IDENTITY: assinatura ad-hoc (uso local, cada pessoa compila na própria máquina)
#   - SIGN_IDENTITY="Developer ID Application: ..." assina com o Developer ID da empresa
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SQL Proxy Menu"
BUNDLE="$ROOT/build/$APP_NAME.app"

cd "$ROOT"
swift build -c release --product SQLProxyMenu
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/SQLProxyMenu" "$BUNDLE/Contents/MacOS/SQLProxyMenu"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$BUNDLE"
else
  codesign --force --sign - "$BUNDLE"
fi

echo "$BUNDLE"
