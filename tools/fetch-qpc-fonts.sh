#!/usr/bin/env bash
# تنزيل خطوط QPC V2 (خط لكل صفحة — مجمع الملك فهد، عبر Quran.com CDN) لوضع التسميع
# الاستخدام: fetch-qpc-fonts.sh [مجلد الهدف] [صفحات...]
#   بلا صفحات: الـ604 كلها (~80 ميجابايت، مرة واحدة). قابل لإعادة التشغيل: يكمل الناقص فقط.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-$DIR/fonts/qpc-v2}"
shift || true
mkdir -p "$TARGET"
cd "$TARGET" || exit 1
BASE="https://static.qurancdn.com/fonts/quran/hafs/v2/woff2"
find . -maxdepth 1 -name '*.part' -delete 2>/dev/null
if [ $# -gt 0 ]; then LIST="$*"; else LIST="$(seq 1 604)"; fi
printf '%s\n' $LIST | xargs -P 3 -I{} sh -c '
  f="p$1.woff2"
  [ -s "$f" ] && exit 0
  curl -sfL --retry 3 --max-time 120 -o "$f.part" "'"$BASE"'/p$1.woff2" && mv "$f.part" "$f"' _ {}
COUNT=$(ls p*.woff2 2>/dev/null | wc -l)
echo "QPC $COUNT"
