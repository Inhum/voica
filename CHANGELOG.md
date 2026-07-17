# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Local offline speech recognition (opt-in).** A new engine switch in Settings → General:
  Cloud (Groq) or Local (offline). The local engine runs Sber's GigaAM v3 model entirely
  on-device via CoreML (Apple Neural Engine): no internet, no API key, punctuation out of
  the box. The model (~400 MB, precompiled CoreML) is downloaded once from a GitHub release
  asset with a progress bar and SHA-256 verification; while it downloads, dictation keeps
  using the cloud. It can be deleted anytime in Settings → Data ("Delete Local Model").
  If the cloud is unreachable and the local model is installed, dictation automatically
  falls back to it with an unobtrusive system notification. Limitations: English words may
  come out transliterated in Cyrillic; the vocabulary hint remains cloud-only, while AI term
  correction works with both engines (it needs a key and network).

## [0.8.0] — 2026-07-12

### Changed
- **Settings reorganized into tabs** (toolbar-style, like the system Settings app):
  General (API key, updates), Dictation (mode, key, output), Vocabulary (terms, AI correction),
  Data (audio, retention, delete). The old single-page window had outgrown a 13" screen.

### Added
- **Model availability check.** When you enable "Fix terms with AI" (and whenever Settings
  opens with it on), Voica pings the chat model and shows a native status: a green checkmark
  if it's available, or a warning with a hint to allow the model in your Groq console if it's
  blocked — no need to read the docs to find out why correction isn't working.
- **Vocabulary character counter.** A live `N / 800` counter under the vocabulary field
  (turns orange over the Whisper prompt budget; the tail is what gets sent).
- **Reset Settings to Defaults** (General tab). Returns all settings to defaults while keeping
  the API key, history, audio and vocabulary — unlike Delete All Data, which wipes everything.

## [0.7.0] — 2026-07-12

### Added
- **AI term correction (opt-in).** After transcription, a Groq language model
  (`qwen/qwen3-32b`, no reasoning) reliably fixes garbled vocabulary terms — matching
  grammatical case and context — in the cases where the Whisper `prompt` hint is powerless
  (near-homophones of common words, e.g. "voice" → "Voica"). Toggle in Settings → Vocabulary;
  adds one small extra request (~1–2 s). Fail-open: on any error or timeout the raw
  transcription is delivered unchanged.

## [0.6.0] — 2026-07-08

### Added
- **Vocabulary.** A new field in Settings → Vocabulary lets you list terms Whisper often
  mishears (names, jargon, anglicisms). They're passed to Whisper as a `prompt` on every
  dictation to bias spelling. It's a hint, not a strict rule, and is capped to fit Whisper's
  prompt budget (the tail is kept).

## [0.5.1] — 2026-07-04

### Changed
- Internal: the transcription history store (SQLite) is now fully serialized through a private
  serial queue, so it is safe to use from any thread. No user-facing changes.

## [0.5.0] — 2026-07-04

### Added
- **Update check.** Voica queries the public GitHub Releases API to see if a newer version is
  available. On launch it checks at most once a day (toggle in Settings → Updates), and the
  new **Check for Updates…** menu item checks on demand. If an update exists, Voica offers to
  open the release page — it never downloads or installs anything by itself. The request is
  anonymous and sends only a `Voica` User-Agent.

### Fixed
- The About window now shows the real app icon (waveform) instead of a generic microphone
  placeholder.

## [0.4.0] — 2026-07-03

### Added
- **Auto-insert** the transcribed text into the active field (synthesizes ⌘V), now the
  default. The text is still copied to the clipboard as a fallback. A new Settings option
  under Dictation lets you switch back to the previous behavior (an editable result window).

## [0.3.2] — 2026-06-30

### Changed
- Sign the app with a local self-signed certificate instead of ad-hoc. This gives a stable
  code-signing identity, so the **Accessibility permission now persists across updates**
  (previously it was lost on every rebuild). Added `scripts/make-cert.sh`.

## [0.3.1] — 2026-06-30

### Changed
- Key-validation status in Settings now uses a native style: a semantic icon (green
  checkmark / red cross) and a spinner while checking, instead of inline glyphs.

## [0.3.0] — 2026-06-30

### Added
- Application icon (waveform on a rounded gradient), generated via CoreGraphics
  (`scripts/make-icon.sh`).

## [0.2.0] — 2026-06-30

### Added
- Bilingual UI (English / Russian) that follows the system language.

### Changed
- App version is read from the bundle (single source of truth) instead of being hardcoded.

## [0.1.0] — 2026-06-29

### Added
- Initial release. Menu-bar dictation: record → Groq Whisper (`whisper-large-v3-turbo`) →
  punctuated text auto-copied to the clipboard and shown in an editable window.
- Push-to-talk and toggle hotkey modes; configurable key.
- History of transcriptions (SQLite) with playback, re-copy, and delete.
- Audio storage with configurable retention (default 30 days).
- Settings: API key (stored in a `0600` file) with a Test button, dictation mode, key,
  retention, and Delete all data (guarded by a random phrase).
- Self-test mode (`--test-all`) and `.dmg` packaging.

[0.8.0]: https://github.com/Inhum/voica/releases/tag/v0.8.0
[0.7.0]: https://github.com/Inhum/voica/releases/tag/v0.7.0
[0.6.0]: https://github.com/Inhum/voica/releases/tag/v0.6.0
[0.5.1]: https://github.com/Inhum/voica/releases/tag/v0.5.1
[0.5.0]: https://github.com/Inhum/voica/releases/tag/v0.5.0
[0.4.0]: https://github.com/Inhum/voica/releases/tag/v0.4.0
[0.3.2]: https://github.com/Inhum/voica/releases/tag/v0.3.2
[0.3.1]: https://github.com/Inhum/voica/releases/tag/v0.3.1
[0.3.0]: https://github.com/Inhum/voica/releases/tag/v0.3.0

<!-- 0.2.0 and 0.1.0 were not tagged as GitHub releases. -->

