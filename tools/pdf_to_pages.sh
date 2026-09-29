#!/usr/bin/env bash
# يحوّل PDF المصحف (طبعة مصحف المدينة ١٤٤١هـ) إلى صور صفحات pages/pNNN.jpg
# الاستخدام: tools/pdf_to_pages.sh [ملف-الـpdf] [الدقة]
set -euo pipefail
cd "$(dirname "$0")/.."
PDF="${1:-tmp/q1441.pdf}"
DPI="${2:-200}"

echo "== معلومات الملف =="
pdfinfo "$PDF" | sed -n '1,20p'

echo "== تحويل عند $DPI نقطة/إنش =="
rm -rf tmp/img && mkdir -p tmp/img
pdftoppm -jpeg -r "$DPI" -jpegopt quality=88 "$PDF" tmp/img/pg
echo "عدد الصور المولدة: $(ls tmp/img | wc -l)"

# إعادة التسمية إلى pNNN.jpg (3 خانات)
mkdir -p pages
for f in tmp/img/pg-*.jpg; do
  n=$(basename "$f" | sed -E 's/pg-0*([0-9]+)\.jpg/\1/')
  printf -v dst "pages/p%03d.jpg" "$n"
  mv "$f" "$dst"
done
echo "== عينة =="
ls pages | head -3
ls pages | tail -3
echo "الإجمالي: $(ls pages | wc -l)"
