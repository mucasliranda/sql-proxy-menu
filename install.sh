#!/usr/bin/env bash
# Instala o SQL Proxy Menu em ~/Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SQL Proxy Menu"
BUNDLE_ID="io.github.mucasliranda.sqlproxymenu"
DEST="$HOME/Applications/$APP_NAME.app"

ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; exit 1; }

find_bin() {
  for dir in /opt/homebrew/bin /usr/local/bin "$HOME/google-cloud-sdk/bin"; do
    [ -x "$dir/$1" ] && { echo "$dir/$1"; return; }
  done
  command -v "$1" 2>/dev/null || true
}

echo "Verificando pré-requisitos…"

major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 13 ] || fail "macOS 13 (Ventura) ou superior é necessário (atual: $(sw_vers -productVersion))"
ok "macOS $(sw_vers -productVersion)"

xcode-select -p >/dev/null 2>&1 || fail "Xcode Command Line Tools não instalado. Rode: xcode-select --install"
command -v swift >/dev/null 2>&1 || fail "swift não encontrado. Rode: xcode-select --install"
ok "Swift $(swift --version 2>&1 | grep -oE 'Swift version [0-9.]+' | head -1 | cut -d' ' -f3)"

proxy="$(find_bin cloud-sql-proxy)"
if [ -n "$proxy" ]; then
  ok "cloud-sql-proxy $("$proxy" --version 2>/dev/null | awk '{print $NF}')"
else
  warn "cloud-sql-proxy não encontrado. Instale com: brew install cloud-sql-proxy"
fi

gcloud_bin="$(find_bin gcloud)"
if [ -n "$gcloud_bin" ]; then
  ok "gcloud encontrado"
else
  warn "gcloud não encontrado. Instale com: brew install --cask google-cloud-sdk"
fi

if [ -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
  ok "Credencial ADC encontrada"
else
  warn "Credencial ADC não encontrada. Rode: gcloud auth application-default login"
fi

echo
echo "Compilando (pode levar um minuto na primeira vez)…"
built="$("$ROOT/scripts/build-app.sh" | tail -1)"
ok "Compilado"

if pgrep -x SQLProxyMenu >/dev/null 2>&1; then
  echo "Fechando a versão em execução…"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -x SQLProxyMenu >/dev/null 2>&1 || break
    sleep 0.25
  done
  pkill -x SQLProxyMenu 2>/dev/null || true
fi

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$built" "$DEST"
ok "Instalado em ~/Applications/$APP_NAME.app"

open "$DEST"
echo
echo "Pronto! O ícone de banco de dados apareceu na barra de menu (canto superior direito)."
echo "Para abrir junto com o Mac: Preferências → Abrir ao iniciar sessão no Mac."
