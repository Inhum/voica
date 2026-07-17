<p align="center"><b>English</b> · <a href="README.ru.md">Русский</a></p>

<p align="center">
  <img src="docs/icon.png" width="128" alt="Voica icon">
</p>

<h1 align="center">Voica</h1>

<p align="center">
  A macOS menu-bar app for voice dictation <b>with punctuation</b> —
  via <a href="https://groq.com">Groq</a> Whisper (<code>whisper-large-v3-turbo</code>)
  or fully offline with a local model (GigaAM v3).
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-black" alt="macOS 13+">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license">
  <img src="https://img.shields.io/badge/built%20with-Swift-orange" alt="Swift">
  <a href="https://deepwiki.com/Inhum/voica"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>
</p>

---

Built-in dictation on macOS/iOS doesn't add punctuation — no periods, commas, or question
marks. Voica does: dictate by a hotkey and get clean, punctuated text inserted right where
you're typing, transcribed via [Groq](https://groq.com) Whisper (`whisper-large-v3-turbo`),
which is fast and cheap — or **fully offline** with a local on-device model (Sber's GigaAM v3,
excellent for Russian), no internet or API key required.

## Features

- **Hotkey dictation** — push-to-talk (hold) or toggle (press to start / stop).
- **Local offline engine (optional)** — switch Settings → General to *Local (offline)* and
  dictation runs entirely on your Mac via Core ML on the Apple Neural Engine (Sber's
  [GigaAM v3](https://github.com/salute-developers/GigaAM) model, MIT, punctuation out of
  the box, excellent Russian). One-time ~400 MB model download with a progress bar; the model
  can be deleted anytime in Settings → Data. If the cloud is unreachable, Voica automatically
  falls back to the local model (with a notification). Trade-offs: English words may come out
  transliterated in Cyrillic, and the vocabulary hint stays cloud-only.
- Recognized text is **inserted into the active field** by default (or shown in an editable
  window — your choice in Settings), and always copied to the clipboard as a fallback.
- **History** of all transcriptions (SQLite): review, re-copy, play back the audio, delete.
- **Audio retention** with auto-cleanup (default 30 days, configurable; text history is kept).
- **Automatic language detection** (works for mixed speech).
- **Vocabulary** — list terms Whisper often mishears (names, jargon, anglicisms) and they're
  passed as a hint on every dictation to bias spelling. Soft limit ~800 characters (Whisper
  only reads the last ~224 tokens of the hint; a live counter in Settings shows the budget).
  Optionally, an **AI pass** (Groq LLM) reliably fixes the terms that still come out
  garbled — matching grammatical case and context.
- **Localized UI** — English and Russian, follows the system language.
- **Update checks** — optionally checks GitHub for a newer version on launch and points you to
  the release page. Never downloads or installs anything by itself; can be turned off.
- API key stored in a **protected file** (`0600`, readable only by you) — never in the repo.
- **Privacy-friendly**: everything stays on your Mac. Audio goes only to Groq for transcription —
  or nowhere at all with the local engine; the only other network call is the optional,
  anonymous update check to GitHub.

## Screenshots

<p align="center">
  <img src="docs/settings-general.png" width="440" alt="Settings — General">
  <img src="docs/settings-vocabulary.png" width="440" alt="Settings — Vocabulary">
  <img src="docs/about.png" width="360" alt="About window">
</p>

## Install

1. Download `Voica-<version>.dmg` from [Releases](https://github.com/Inhum/voica/releases)
   (or build from source — see below).
2. Open the `.dmg` and drag **Voica** to **Applications**.
3. The app isn't notarized, so on first launch macOS warns about an unidentified developer:
   System Settings → Privacy & Security → **Open Anyway**. After that it opens normally.

## First run & permissions

On first use macOS asks for two permissions:

- **Microphone** — to record (prompted on your first dictation).
- **Accessibility** — for the global hotkey:
  System Settings → Privacy & Security → **Accessibility** → enable Voica.

Then the Settings window opens — paste your **Groq API key** (`gsk_…`), click **Test**,
then **Save**. Get a key at [console.groq.com/keys](https://console.groq.com/keys).
Don't want a key or the cloud? Choose **Local (offline)** in Settings → General instead —
Voica downloads the model (~400 MB, once) and no key is needed at all.

## Usage

- **Push-to-talk** (default): hold Right ⌥ Option, speak, release — text arrives in ~a second.
- **Toggle**: one press of the chosen key starts, another stops.
- Or click **Dictate** in the menu (manual start/stop, no hotkey needed).

The menu-bar icon reflects state: idle → recording (pulsing) → sending to Groq.

## Settings

Organized into tabs (like the system Settings app): **General** — speech engine
(Cloud / Local), API key (with a Test button), update check, reset to defaults;
**Dictation** — mode (push-to-talk / toggle), hotkey, output; **Vocabulary** — your terms
with a live budget counter and the AI correction toggle (with a model availability check);
**Data** — audio storage, retention, local model deletion, and **Delete all data**
(guarded by a random phrase).

## Where data is stored

```
~/Library/Application Support/com.ushakov.voica/history.sqlite   # history
~/Library/Application Support/com.ushakov.voica/audio/           # audio recordings
~/Library/Application Support/com.ushakov.voica/credentials      # API key (0600)
~/Library/Application Support/com.ushakov.voica/models/          # local model (if downloaded)
~/Library/Preferences/com.ushakov.voica.plist                    # settings
```

## Bring your own Groq key

The key is only needed for the **cloud** engine (and for AI term correction); the local
engine works without one. Voica uses **your own** Groq API key (BYO-key) — the app never
ships or shares anyone's key.
Each user gets a free key at [console.groq.com](https://console.groq.com); usage is subject
to [Groq's Terms of Use](https://groq.com/terms-of-use). Free-tier limits (whisper-large-v3-turbo):
20 req/min, 2000/day, 7200 audio-seconds/hour — far more than dictation needs.

**If you enable AI term correction** (Settings → Vocabulary), Voica also calls the chat model
`qwen/qwen3-32b`. If your Groq organization restricts model access, allow this model at
console.groq.com → Settings → Limits — otherwise the correction silently falls back to the
raw transcription (fail-open by design).

## Build from source

Only Command Line Tools are required (`xcode-select --install`); full Xcode is not needed.

```bash
./scripts/make-cert.sh       # once: local self-signed cert for a stable signature
./scripts/build.sh           # builds build/Voica.app (release)
./scripts/run.sh             # build + run with logs in the terminal
./scripts/package.sh         # builds build/Voica-<version>.dmg
./build/Voica.app/Contents/MacOS/Voica --test-all   # self-test
```

`make-cert.sh` creates a self-signed signing certificate in your keychain. Without it the
build is signed ad-hoc, and the Accessibility permission gets lost on every update (macOS
can't stably identify an ad-hoc app). With the certificate it persists. See
[docs/ROADMAP.md](docs/ROADMAP.md) for distribution, auto-update, and cross-platform notes.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). This is a
spare-time project, so responses may be slow and not every feature request will be accepted.

## Acknowledgements

Voica was built largely with [Claude Code](https://claude.com/claude-code), Anthropic's
agentic coding tool, as an AI pair-programmer.

## License

[MIT](LICENSE) © 2026 Ivan Ushakov
