# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [0.9.10] — 2026-08-08 — Recording bar, double-tap to start, batch delete

### Added
- **Recording bar** — a floating capsule at the bottom of the screen shows that dictation is on:
  a live waveform plus **×** (cancel — the recording is dropped, nothing is transcribed) and
  **✓** (stop and transcribe). When recognition starts it turns into a spinner with
  “Recognizing…”, so one indicator covers the whole run and the menu-bar icon stays untouched.
  Turn it off in Settings → Dictation to get the old behaviour back (pulsing menu-bar icon).
- **Cancel a dictation** — previously there was no way to abort; the recording is discarded
  without being sent anywhere.
- **Double-tap to start** (Toggle mode, on by default) — press the key twice within 0.35 s to
  start; a single press still stops. Fixes accidental starts. Switch it off in
  Settings → Dictation. Push-to-talk is unaffected.
- **Multi-select in History** — pick several entries with Cmd/Shift (and Cmd+A), then delete
  them in one go; the confirmation tells you how many. The Delete key and a right-click menu do
  the same. With more than one entry selected the detail pane shows the count.
- **“Support the project”** in Settings → About — a link to [Boosty](https://boosty.to/voica).
  Voica stays free in full: no subscription, no paid features, donations are entirely optional.

### Fixed
- **The menu-bar icon was always monochrome** — the recording and recognition states were meant
  to be tinted since the very first versions, but the tint was silently dropped: a status-item
  button ignores `contentTintColor` for both template and non-template images. The colour now
  comes from the symbol’s own palette.
- The model-preparation HUD (“Preparing the recognition model…”) had square corners — a rounded
  layer doesn’t clip a behind-window blur. It now shares its look with the recording bar.

## [0.9.9] — 2026-07-30 — About tab + history export

### Added
- **History export** — an “Export…” button in the History window exports the whole history to
  **Markdown, CSV, or JSON** (pick the format in the save dialog). Text + metadata (date, language,
  duration, engine/model); CSV includes a UTF-8 BOM for Excel and RFC-4180 escaping, JSON also
  carries the id and audio filename. The audio itself isn’t included.
- **About tab** — About moved from a separate window into a fifth Settings tab: icon, version,
  a privacy summary, an in-tab “Check for Updates” (with a Download link when a newer version is
  available) and the “check on launch” toggle, plus GitHub and license. The menu-bar “About Voica”
  item now opens this tab.

### Fixed
- The “nothing recognized” message no longer says “Whisper” when the local GigaAM engine is
  active — it’s now engine-neutral.

## [0.9.8] — 2026-07-24 — Model selection: dynamic chat model + recognition model & language

### Added
- **Recognition model & language** picker (Settings → Dictation, cloud engine): choose Turbo
  (faster) or Large v3 (more accurate), and force a recognition language (Auto / Russian /
  English) — forcing helps short phrases that auto-detect gets wrong. The local engine (GigaAM)
  is Russian-only and ignores these. History records the model actually used.

### Changed
- The AI term-fixing model is no longer hard-coded. The app now fetches the live model list
  with your key (`GET /v1/models`), filters chat-capable models, and picks the best available
  by a priority chain (`llama-3.3-70b-versatile` → `openai/gpt-oss-120b` → `openai/gpt-oss-20b`
  → `llama-3.1-8b-instant` → `gemma2-9b-it`), falling back to the first available.
- Vocabulary settings gained an **AI model** picker: “Recommended (automatic)” by default, with
  the full live list for power users. Visible only when AI term-fixing is on.

### Fixed
- **Self-healing:** if Groq removes or renames the selected model (as with `qwen/qwen3-32b` in
  0.9.3, which returned 404), the app now switches to the recommended model on its own — no
  urgent release needed. A stale saved choice migrates to “automatic”, and a 404 during dictation
  triggers a background re-resolve so the next dictation uses a live model. Dictation stays
  fail-open throughout.

## [0.9.7] — 2026-07-19 — Local engine: overlapping chunks (no dropped words)

### Fixed
- The local engine split long recordings at hard 25-second boundaries, so a word or its
  punctuation could be lost or duplicated at the seam. Adjacent windows now overlap ~2s and
  the duplicate at the join is trimmed by word match (case/punctuation-insensitive); otherwise
  a plain space-join. Parity with the Windows port, which fixed this first.

## [0.9.6] — 2026-07-19 — Fix: history metadata overlapping buttons

### Fixed
- In a narrow History window the metadata line (date · language · duration · model) ran
  under the Copy/Play/Delete buttons. It now truncates before them.

## [0.9.5] — 2026-07-19 — History shows the engine/model

### Added
- History now shows **which engine/model** produced each transcript in the metadata line
  (date · language · duration · **model**), e.g. `whisper-large-v3-turbo` or
  `gigaam-v3-e2e-ctc`. Parity with the Windows port, which already displayed it.

## [0.9.4] — 2026-07-18 — Local engine: “preparing model” indicator

### Added
- On the **first local dictation** after launch, a small floating **“Preparing the
  recognition model…”** HUD appears while Core ML does its one-time on-device model load
  (tens of seconds). Previously the app looked frozen during this wait. Subsequent
  dictations, where the model is already in memory, show nothing.

## [0.9.3] — 2026-07-18 — Fix: AI term correction model (Groq removed qwen3-32b)

### Fixed
- AI term correction failed with **HTTP 404** because Groq removed the hardcoded
  `qwen/qwen3-32b` model. Switched to the production model `llama-3.3-70b-versatile`
  and dropped the qwen-specific `reasoning_effort` parameter.
- The model-availability check now reports a **404** clearly (“model unavailable — Groq may
  have renamed or removed it”) instead of a bare `HTTP 404`.

## [0.9.2] — 2026-07-18 — Fix: runs on macOS 13+ again

### Fixed
- Release builds now run on **macOS 13 and later** as documented. The binary was being
  stamped with the build machine's macOS as its minimum (so CI-built 0.9.0/0.9.1 refused
  to launch on anything older than the runner). The build now passes an explicit
  `-target arm64-apple-macos13.0`, kept in sync with `LSMinimumSystemVersion`.

## [0.9.1] — 2026-07-17 — Both models named everywhere

### Changed
- Settings → General now names the **active model** next to the engine switch:
  `whisper-large-v3-turbo (Groq cloud)` or `GigaAM v3 — runs on this Mac`.
- The About window tagline and the README headers (both languages) mention both engines
  consistently — cloud Groq Whisper and the local GigaAM model.

## [0.9.0] — 2026-07-17 — Local offline engine (GigaAM)

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

