# Voica — план реализации

Меню-бар приложение для macOS: диктуешь голосом → получаешь текст **с пунктуацией**
(чего не умеет встроенная диктовка iOS/macOS). Транскрибация через **Groq Whisper**
(`whisper-large-v3-turbo`, прямой доступ к `api.groq.com`).

Старт — только macOS. Windows 11 и iOS — потенциально позже, отдельными проектами
(нативный код и модель разрешений не переносятся напрямую).

## Требования

| Область | Решение |
|---|---|
| Триггер | PTT (удержание) и toggle (нажал/нажал), переключается в Settings, по умолчанию **PTT** |
| Выдача текста | Окно результата (редактируемое) + автокопия в буфер. Кнопка Copy — иконка→галочка |
| История | Все транскрибации в SQLite (текст + метаданные) |
| Аудио | Хранятся записи, retention по умолчанию **30 дней**, настраивается |
| Язык | Автоопределение (основной русский + вкрапления английского) |
| Постобработка | Только Whisper, без LLM. Free tier Groq |
| Ключ | В Keychain. Ввод при первом старте + поле в Settings (с «Проверить») |
| Удаление данных | Delete all data с подтверждением случайной фразой (защита от дурака) |

## Стек

- Swift + AppKit (меню-бар, окна), AVFoundation (запись), URLSession (Groq),
  sqlite3 (история), Keychain Services (ключ).
- Сборка `swiftc` → `.app` (Info.plist, ad-hoc codesign) → `.dmg`. Без Xcode-проекта.

## Данные (вне .app, переживают обновление)

- `~/Library/Application Support/com.ushakov.voica/` — `history.sqlite` + `audio/`
- `~/Library/Preferences/com.ushakov.voica.plist` — настройки (UserDefaults)
- Keychain — API-ключ
- `~/Library/Logs/Voica/` — логи

## Лимиты Groq (free tier, whisper-large-v3-turbo)

20 req/min, 2000 req/day, 7200 audio-sec/hour, 28800 audio-sec/day.
Файл ≤ 25 МБ ≈ ~100 минут речи при записи 16кГц моно AAC. Для диктовки недостижимо.

## Этапы

1. **Каркас** — репо, скелет `.app`, иконка меню-бара, build/run-скрипты. ← *текущий*
2. **Запись + Groq** — hotkey (PTT), Recorder, GroqClient, текст в буфер + окно результата.
3. **Хранилище** — SQLite, сохранение аудио, retention-чистка, окно History.
4. **Settings + Keychain** — ключ, режим, хоткей, retention, Delete all data.
5. **About + полировка** — About, пульсация иконки, ошибки/лимиты, самотест `--test-all`.
6. **Упаковка + доки** — `.dmg`, README.

## Разрешения macOS (один раз)

- **Microphone** — запись.
- **Input Monitoring / Accessibility** — глобальный хоткей.
