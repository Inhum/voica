#!/usr/bin/env bash
# Создаёт локальный self-signed сертификат для подписи Voica и кладёт его в
# login keychain. Нужен один раз. Стабильная подпись → разрешение Accessibility
# держится между запусками и обновлениями (в отличие от ad-hoc).
#
# Сертификат self-signed и не доверенный системой — для *подписи* этого достаточно
# (Gatekeeper всё равно потребует «Open Anyway» при первом запуске). Приватный ключ
# остаётся только в связке ключей; временные файлы удаляются.
set -euo pipefail

IDENTITY="Voica Self-Signed"

# -v (только доверенные) не показывает self-signed, поэтому ищем без него.
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "Сертификат уже есть в связке ключей:"
    security find-identity -p codesigning | grep "$IDENTITY"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = Voica Self-Signed
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null

# -legacy: OpenSSL 3.x иначе создаёт p12 в формате, который macOS security не импортирует.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout pass:voica -name "$IDENTITY" 2>/dev/null

# -A: ключ доступен приложениям без запроса (локальный dev-сертификат).
security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P voica -A

echo "Готово. Идентичность для подписи:"
security find-identity -p codesigning | grep "$IDENTITY"
