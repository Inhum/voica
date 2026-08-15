#!/usr/bin/env bash
# Собирает release-сборку и упаковывает в build/Voica-<версия>.dmg
# с ярлыком /Applications для перетаскивания.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAME="Voica"
"$ROOT/scripts/build.sh" release

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/${NAME}-${VERSION}.dmg"
STAGE="build/dmg"

echo "→ Упаковка ${DMG} …"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "build/$NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Файловая система образа задана ЯВНО. Без -fs hdiutil выбирает сам, и выбор нестабилен:
# 0.9.12 собрался в HFS+ (492 КБ), 0.9.13 на том же раннере и том же коде — в APFS (747 КБ).
# Приложение при этом одинаковое, разница целиком в служебных структурах контейнера APFS.
# Образ только читается (смонтировал → перетащил → выбросил), поэтому снимки, клоны и
# шифрование APFS не нужны, а четверть мегабайта в загрузке — нужна.
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ Готово: $DMG"
