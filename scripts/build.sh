#!/usr/bin/env bash
# Собирает build/Voica.app из исходников и подписывает ad-hoc.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAME="Voica"
APP="build/$NAME.app"
CONFIG="${1:-release}"   # release | debug

echo "→ Сборка $NAME ($CONFIG)…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Явный таргет с минимальной версией macOS. БЕЗ него swiftc проставляет minos по SDK
# машины сборки (на новом macOS/CI-раннере это будет 15/26), и .app не запустится на
# более старых системах, ХОТЯ Info.plist разрешает 13.0. Держим в синхроне с
# LSMinimumSystemVersion в Info.plist. arm64 — приложению нужен Apple Silicon (ANE).
MIN_MACOS=13.0
TARGET="arm64-apple-macos${MIN_MACOS}"

SWIFT_FLAGS=(-O -swift-version 5 -target "$TARGET")
[ "$CONFIG" = "debug" ] && SWIFT_FLAGS=(-Onone -g -swift-version 5 -target "$TARGET")

swiftc "${SWIFT_FLAGS[@]}" -o "$APP/Contents/MacOS/$NAME" Sources/*.swift

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"   # локализация (en/ru)
[ -f Resources/Voica.icns ] && cp Resources/Voica.icns "$APP/Contents/Resources/"
for f in Resources/gigaam-*; do   # ресурсы локального движка (словарь, окно, мел-банк)
    [ -f "$f" ] && cp "$f" "$APP/Contents/Resources/"
done

# Подпись. Если есть локальный сертификат «Voica Self-Signed» — подписываем им
# (стабильная идентичность → разрешение Accessibility держится между обновлениями).
# Иначе откат на ad-hoc. Сертификат создаётся один раз: ./scripts/make-cert.sh
#
# ⚠️ Откат на ad-hoc обязан быть ГРОМКИМ. Он выглядит как успешная сборка, а расплата
# приходит позже и не связывается с причиной: ad-hoc привязывает удостоверение к хешу
# бинаря, поэтому каждая пересборка — новое приложение для macOS, и разрешение
# Accessibility приходится выдавать заново, а вставка текста до этого не работает.
# Самый коварный путь сюда — ЗАПЕРТАЯ связка ключей: сертификат есть, но
# `security find-identity` его не видит, и скрипт молча уходит в ad-hoc.
IDENTITY="Voica Self-Signed"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    SIGN="$IDENTITY"; NOTE="сертификатом ${IDENTITY}"
else
    SIGN="-"; NOTE="ad-hoc"
    echo "⚠ Сертификат «$IDENTITY» не найден — подпись будет ad-hoc."
    echo "  Причин две: сертификата нет (./scripts/make-cert.sh) ИЛИ связка ключей заперта."
    echo "  Проверить связку: security unlock-keychain login.keychain"
fi

# Ошибку codesign НЕ глушим: раньше она уходила в /dev/null, и причину отказа
# было не узнать в принципе.
if ! SIGN_ERR="$(codesign --force --sign "$SIGN" "$APP" 2>&1)"; then
    echo "⚠ codesign не сработал (запуск всё равно возможен):"
    echo "  ${SIGN_ERR:-без сообщения}"
else
    echo "→ Подписано $NOTE"
fi

# Проверяем РЕЗУЛЬТАТ, а не намерение: подпись сертификатом даёт в требованиях
# «certificate leaf», ad-hoc — «cdhash». Единственный надёжный способ отличить.
if codesign -d --requirements - "$APP" 2>&1 | grep -q "certificate leaf"; then
    :
else
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║ ВНИМАНИЕ: приложение подписано AD-HOC, а не сертификатом.             ║"
    echo "║ macOS будет считать каждую пересборку новым приложением и заново      ║"
    echo "║ просить доступ к Accessibility; до выдачи вставка текста не работает. ║"
    echo "║ Лечится: security unlock-keychain login.keychain  или  make-cert.sh   ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""
fi

echo "✓ Готово: $APP"
