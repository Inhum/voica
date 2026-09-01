#!/usr/bin/env python3
"""Сравнивает chat-модели Groq на НАШЕЙ задаче — исправлении терминов из словаря (§6.1).

Зачем: порядок приоритет-цепочки в GroqClient.recommendedChatModels исторически задан по
размеру моделей, а это прокси, а не измерение. Чужие бенчмарки меряют общий интеллект и
ничего не говорят про правку терминов в русском тексте. Здесь — замер на живых искажениях,
собранных из истории диктовок.

Промпт НЕ дублируется: скрипт берёт его у самого приложения (`--print-prompt`), иначе копия
разошлась бы с рабочей и замер молча измерял бы не то. Значит перед запуском нужна сборка:

    ./scripts/build.sh && ./scripts/eval-chat-models.py

Ключ читается оттуда же, откуда его берёт приложение. Учти лимиты бесплатного тарифа
(8K токенов в минуту) — между запросами стоят паузы, полный прогон идёт пару минут.

⚠️ Ловушки (пустой список ожиданий) важнее находок: они ловят порчу обычной русской речи,
и на них обе проверенные модели спотыкались, хотя счёт по находкам был одинаковый.
"""
import json, pathlib, re, subprocess, sys, time, urllib.error, urllib.request

APP = "build/Voica.app/Contents/MacOS/Voica"
KEY = pathlib.Path.home() / "Library/Application Support/com.ushakov.voica/credentials"
VOCAB = ("Claude Code, Cowork, ChatGPT, Voica, focus-radio, Groq, API, ЕИС, оферта, "
         "GigaAM, Tailscale, app-connector, exit-node, DeepSeek")
DEFAULT_MODELS = ["openai/gpt-oss-120b", "qwen/qwen3.8-27b"]

# (что услышал движок, какие термины ОБЯЗАНЫ появиться). Пустой список — ловушка: обычная
# русская речь, текст менять нельзя ни одним символом.
CASES = [
    ("Проверка диктовки на локальном движке с термином Dпсик в словаре.", ["DeepSeek"]),
    ("Поставил диппсих. Проверка клодкод, проверка.", ["DeepSeek", "Claude Code"]),
    ("Открой клод код и поставь Dpсик.", ["Claude Code", "DeepSeek"]),
    ("Проверка диктовки на локальном движке. Искусственный интеллект. Эй-ай.", ["AI"]),
    ("Настрой Tail scale Time exit not a Up connector.", ["Tailscale", "app-connector"]),
    ("Включи Fоcс радио. Работаю в Cowork.", ["focus-radio"]),
    ("Ключ от грок лежит в настройках. Это апи.", ["Groq", "API"]),
    ("Войс пишет с пунктуацией.", ["Voica"]),
    ("А, да, вот ещё диктую: Focus раadio fixturms Wathi, Deepsc, проверка по словарю.",
     ["focus-radio", "DeepSeek"]),
    ("Вика прислала кода на 200 строк.", []),
    ("Папа купил усы для костюма.", []),
    ("Пришла депеша срочная.", []),
    ("Я учил греческий, а не турецкий.", []),
    ("Колодка тормозная. Код заказа 105.", []),
    ("затем чат увидит результат и vice versa", []),
]


def prompt_for(text):
    if not pathlib.Path(APP).exists():
        sys.exit(f"нет сборки {APP} — сначала ./scripts/build.sh")
    return subprocess.run([APP, "--print-prompt", VOCAB, text],
                          capture_output=True, text=True, check=True).stdout


def ask(key, model, text):
    body = json.dumps({"model": model, "temperature": 0, "max_completion_tokens": 4096,
                       "messages": [{"role": "user", "content": prompt_for(text)}]}).encode()
    req = urllib.request.Request(
        "https://api.groq.com/openai/v1/chat/completions", data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json",
                 # Без User-Agent Groq отдаёт 403 — тот же код, что «модель не разрешена
                 # организации». Легко принять одно за другое, поэтому шлём явно.
                 "User-Agent": "voica-eval"})
    for attempt in range(6):
        try:
            r = json.loads(urllib.request.urlopen(req, timeout=90).read())
            break
        except urllib.error.HTTPError as e:
            if e.code == 429:                       # лимит бесплатного тарифа — подождать
                time.sleep(20 + attempt * 15)
                continue
            return f"<ОШИБКА HTTP {e.code}>", 0
        except Exception as e:                      # noqa: BLE001 — замер не должен падать
            return f"<ОШИБКА {e}>", 0
    else:
        return "<ОШИБКА лимит>", 0
    c = r["choices"][0]["message"]["content"]
    # Та же вычистка рассуждений, что в GroqClient.stripReasoning (§6.1).
    c = re.sub(r"<think[^>]*>.*?</think>", "", c, flags=re.S | re.I)
    return re.sub(r"<think[^>]*>.*", "", c, flags=re.S | re.I).strip(), r["usage"]["total_tokens"]


def main():
    key = KEY.read_text().strip()
    models = sys.argv[1:] or DEFAULT_MODELS
    for model in models:
        ok = tokens = 0
        print(f"\n╔══ {model}")
        for text, want in CASES:
            out, used = ask(key, model, text)
            tokens += used
            if want:
                miss = [w for w in want if w not in out]
                good, note = not miss, "" if not miss else "  не нашла: " + ", ".join(miss)
            else:
                good = out.strip() == text.strip()
                note = "" if good else "  ИСПОРТИЛА ОБЫЧНЫЙ ТЕКСТ"
            ok += good
            print(f"║ {'✓' if good else '✗'} {out[:96]}{note}")
            time.sleep(4)
        avg = tokens // len(CASES) if tokens else 0
        print(f"╚══ верно {ok} из {len(CASES)} · ~{avg} токенов на диктовку "
              f"(лимиты free tier: {8000 // max(avg, 1)}/мин, {200000 // max(avg, 1)}/сутки)")


if __name__ == "__main__":
    main()
