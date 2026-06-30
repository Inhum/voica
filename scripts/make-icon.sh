#!/usr/bin/env bash
# Генерирует Resources/Voica.icns из scripts/make-icon.swift.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ICONSET="build/Voica.iconset"
mkdir -p build
rm -rf "$ICONSET"

swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o Resources/Voica.icns

cp "$ICONSET/icon_256x256.png" build/voica-icon-preview.png   # для предпросмотра
rm -rf "$ICONSET"
echo "✓ Resources/Voica.icns"
