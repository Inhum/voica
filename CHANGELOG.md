# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

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

[0.4.0]: https://github.com/Inhum/voica/releases/tag/v0.4.0
[0.3.2]: https://github.com/Inhum/voica/releases/tag/v0.3.2
[0.3.1]: https://github.com/Inhum/voica/releases/tag/v0.3.1
[0.3.0]: https://github.com/Inhum/voica/releases/tag/v0.3.0

<!-- 0.2.0 and 0.1.0 were not tagged as GitHub releases. -->

