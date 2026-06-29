# Voica

Меню-бар приложение для macOS: диктуешь голосом — получаешь текст **с пунктуацией**.
Транскрибация через [Groq](https://groq.com) Whisper (`whisper-large-v3-turbo`).

> Встроенная диктовка iOS/macOS не расставляет знаки препинания. Voica — расставляет.

## Статус

🚧 В разработке. Текущий этап — каркас приложения. План: [PLAN.md](PLAN.md).

## Сборка из исходников

Нужны только Command Line Tools (`xcode-select --install`), полный Xcode не требуется.

```bash
./scripts/build.sh        # собирает build/Voica.app
./scripts/run.sh          # сборка + запуск с логами в терминале
```

## Лицензия

[MIT](LICENSE) © 2026 Ivan Ushakov
