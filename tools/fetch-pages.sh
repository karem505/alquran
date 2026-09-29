#!/usr/bin/env bash
# تنزيل صفحات المصحف الـ٦٠٤ (طبعة مصحف المدينة النبوية — إطار ذهبي، 807×1205)
# الاستخدام: fetch-pages.sh [مجلد الهدف] — الافتراضي: مجلد pages بجانب المشروع
# قابل لإعادة التشغيل: يكمل الناقص فقط (كل ملف يُنزَّل إلى .part ثم يُنقل)
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-$DIR/pages}"
mkdir -p "$TARGET"
cd "$TARGET"
BASE="https://raw.githubusercontent.com/QuranHub/quran-pages-images/main/kfgqpc/hafs-wasat"
echo "→ تنزيل 604 صفحة إلى $TARGET ..."
find . -maxdepth 1 -name '*.part' -delete 2>/dev/null
seq 1 604 | xargs -P 12 -I{} sh -c '
  f="$(printf "p%03d.jpg" "$1")"
  [ -s "$f" ] && exit 0
  curl -sL --retry 3 --max-time 180 -o "$f.part" "'"$BASE"'/$1.jpg" && mv "$f.part" "$f"' _ {}
COUNT=$(ls p*.jpg 2>/dev/null | wc -l)
echo "تم ✓ ($COUNT صفحة)"
if [ "$COUNT" -ne 604 ]; then
  echo "⚠ صفحات ناقصة ($COUNT من 604) — أعد تشغيل الأمر لإكمال الناقص"
  exit 1
fi
