#!/usr/bin/env bash
# نشر إصدار جديد من تطبيق القرآن الكريم
# الاستخدام: packaging/release.sh 1.1.0
# الخطوات: تحديث pkgver → commit + وسم → بناء الحزمة → تحديث فرع المستودع repo → GitHub Release
set -euo pipefail
VER="${1:?الاستخدام: packaging/release.sh <رقم الإصدار مثل 1.1.0>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GIT="git -C $ROOT"
GH="${GH:-$(command -v gh)}"
cd "$ROOT"

# 1) تحديث رقم الإصدار في PKGBUILD
sed -i "s/^pkgver=.*/pkgver=$VER/" packaging/PKGBUILD
$GIT add -A
$GIT -c user.email="karem@ailigent.ai" -c user.name="Karem" commit -m "إصدار v$VER" || true
$GIT tag "v$VER" 2>/dev/null || true
$GIT push origin master --tags

# 2) بناء الحزمة (يتطلب تحديث sha256 يدويًا أول مرة لكل إصدار)
WORK="$(mktemp -d)"
cp packaging/PKGBUILD "$WORK/"
(cd "$WORK" && makepkg -f --noconfirm)
PKG=$(ls "$WORK"/alquran-"$VER"-1-any.pkg.tar.zst)

# 3) تحديث فرع مستودع pacman (repo branch)
REPO="$(mktemp -d)"
$GIT clone -q --branch repo --single-branch "https://github.com/karem505/alquran.git" "$REPO"
cp "$PKG" "$REPO/x86_64/"
(cd "$REPO/x86_64" && repo-add alquran.db.tar.gz "alquran-$VER-1-any.pkg.tar.zst" >/dev/null)
rm -f "$REPO/x86_64/alquran.db" "$REPO/x86_64/alquran.files"
cp "$REPO/x86_64/alquran.db.tar.gz" "$REPO/x86_64/alquran.db"
cp "$REPO/x86_64/alquran.files.tar.gz" "$REPO/x86_64/alquran.files"
(cd "$REPO" && git add -A && git -c user.email="karem@ailigent.ai" -c user.name="Karem" commit -q -m "مستودع pacman: alquran $VER-1" && git push -q origin repo)

# 4) GitHub Release + الملفات
"$GH" release create "v$VER" --repo karem505/alquran --title "القرآن الكريم $VER" --notes "إصدار $VER" "$PKG"
echo "تم ✓ — الإصدار v$VER منشور (المستودع + Release)"
