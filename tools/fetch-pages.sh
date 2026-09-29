#!/usr/bin/env bash
# تنزيل صفحات المصحف الـ٦٠٤ (طبعة مصحف المدينة النبوية — إطار ذهبي، 807×1205)
# تُحفظ باسم p001.jpg ... p604.jpg داخل مجلد pages/
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$DIR/pages"
cd "$DIR/pages"
BASE="https://raw.githubusercontent.com/QuranHub/quran-pages-images/main/kfgqpc/hafs-wasat"
echo "→ تنزيل 604 صفحة إلى $DIR/pages ..."
seq 1 604 | xargs -P 12 -I{} sh -c 'curl -sL --retry 3 --max-time 120 -o "$(printf "p%03d.jpg" "$1")" "'"$BASE"'/$1.jpg"' _ {}
COUNT=$(ls p*.jpg 2>/dev/null | wc -l)
echo "تم ✓ ($COUNT صفحة)"
if [ "$COUNT" -ne 604 ]; then echo "⚠ العدد غير مكتمل — أعد تشغيل السكربت لإكمال الناقص"; exit 1; fi
