#!/usr/bin/env bash
# إنشاء اختصار التطبيق في قائمة البرامج + تثبيت الأيقونة
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$APPS" "$ICONS"

cp "$DIR/assets/icon.svg" "$ICONS/alquran.svg"

cat > "$APPS/alquran.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=القرآن الكريم
Name[en]=Al-Quran
GenericName=Quran Reader
Comment=مصحف المدينة النبوية بالرسم العثماني — صفحتان متجاورتان، بحث وعلامات حفظ
Exec=qs -p "$DIR/shell.qml"
Icon=alquran
Terminal=false
Categories=Education;Literature;Religion;
Keywords=Quran;Qur'an;قرآن;القرآن;مصحف;الرسم العثماني;
StartupWMClass=alquran
StartupNotify=true
EOF

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" >/dev/null 2>&1 || true
echo "تم ✓ — افتح التطبيق من قائمة البرامج باسم «القرآن الكريم»"
