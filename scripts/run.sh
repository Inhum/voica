#!/usr/bin/env bash
# Пересобирает и запускает приложение напрямую, чтобы видеть логи в терминале.
# Это меню-бар агент — иконка появится в строке меню, окна в доке не будет.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build.sh" "${1:-debug}"

echo "→ Запуск (Ctrl+C для остановки)…"
exec "$ROOT/build/Voica.app/Contents/MacOS/Voica"
