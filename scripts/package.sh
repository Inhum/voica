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

hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ Готово: $DMG"
