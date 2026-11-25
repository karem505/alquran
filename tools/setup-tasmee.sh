#!/usr/bin/env bash
# تجهيز وضع التسميع (مرة واحدة): محرك Node (Tilawa + onnxruntime-node) وخطوط صفحات QPC
# الاستخدام: setup-tasmee.sh [--no-fonts]
# - التطوير (المستودع قابل للكتابة): يثبّت الحزم في engine/ داخل المستودع.
# - التركيب النظامي (/usr/share/...): ينسخ engine/ إلى ~/.local/share/alquran/engine ويثبّت هناك.
# يطبع سطورًا قصيرة يقرؤها التطبيق: "STEP <name>" و"OK <dir>" و"ERR <سبب>".
set -u
APP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/alquran"

need_node() {
  command -v node >/dev/null 2>&1 || { echo "ERR node"; exit 2; }
  local v; v="$(node -p 'process.versions.node' 2>/dev/null)"
  node -e 'const [a,b]=process.versions.node.split(".").map(Number); process.exit(a>20||(a===20&&b>=12)?0:1)' \
    || { echo "ERR node-version $v"; exit 2; }
  command -v npm >/dev/null 2>&1 || { echo "ERR npm"; exit 2; }
}

need_node
if [ -w "$APP/engine" ]; then
  ENG="$APP/engine"
else
  ENG="$DATA/engine"
  mkdir -p "$ENG"
  cp "$APP/engine/package.json" "$APP/engine/package-lock.json" "$APP/engine/"*.mjs "$ENG/"
  mkdir -p "$ENG/tools"
  cp "$APP/engine/tools/"*.mjs "$ENG/tools/"
fi
if [ ! -d "$ENG/node_modules/@tilawa/core" ] || [ ! -d "$ENG/node_modules/onnxruntime-node" ]; then
  echo "STEP npm"
  (cd "$ENG" && nice -n 10 npm ci --omit=dev --no-audit --no-fund >/dev/null 2>&1) || { echo "ERR npm-install"; exit 3; }
fi
echo "OK $ENG"

if [ "${1:-}" != "--no-fonts" ]; then
  if [ -w "$APP" ] && [ -f "$APP/pages/p604.jpg" ]; then FONTS="$APP/fonts/qpc-v2"; else FONTS="$DATA/qpc-v2"; fi
  echo "STEP fonts"
  nice -n 19 bash "$APP/tools/fetch-qpc-fonts.sh" "$FONTS"
fi
