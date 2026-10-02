#!/usr/bin/env bash
# Remove o SQL Proxy Menu. Use --purge para apagar também configuração e logs.
set -euo pipefail

APP_NAME="SQL Proxy Menu"
BUNDLE_ID="io.github.mucasliranda.sqlproxymenu"

if pgrep -x SQLProxyMenu >/dev/null 2>&1; then
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  sleep 1
  pkill -x SQLProxyMenu 2>/dev/null || true
fi

rm -rf "$HOME/Applications/$APP_NAME.app"
echo "App removido."

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/Library/Application Support/SQLProxyMenu" "$HOME/Library/Logs/SQLProxyMenu"
  echo "Configuração e logs removidos."
else
  echo "Configuração mantida em ~/Library/Application Support/SQLProxyMenu (use --purge para apagar)."
fi
