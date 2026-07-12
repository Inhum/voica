# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Instead, use GitHub's private
[security advisories](https://github.com/Inhum/voica/security/advisories/new) to report
privately, or contact the maintainer ([@Inhum](https://github.com/Inhum)).

You'll get a response as soon as reasonably possible (this is a spare-time project).

## How Voica handles your data

- Your Groq API key is stored in a local file with `0600` permissions
  (`~/Library/Application Support/com.ushakov.voica/credentials`), readable only by your
  user. It is sent only to Groq, over HTTPS, in the `Authorization` header.
- Audio recordings and transcription history stay on your Mac (SQLite + local files).
  Audio is sent to Groq only for transcription.
- **Update check:** Voica queries the public GitHub Releases API
  (`api.github.com/repos/Inhum/voica/releases/latest`) to compare versions. The request is
  anonymous (no token, no personal data) and sends only a `Voica` User-Agent. It runs at most
  once a day on launch and can be turned off in Settings → Updates. Voica never downloads or
  installs anything by itself — it only opens the release page in your browser.
- **AI term correction (optional, off by default):** when enabled in Settings → Vocabulary,
  the transcribed text is additionally sent to a Groq chat model (same `api.groq.com`, same
  BYO key) to fix garbled vocabulary terms. No extra parties are involved.
- Voica has no backend and no telemetry. Its only network calls are to `api.groq.com`
  (transcription, and the optional AI term correction) and `api.github.com` (the optional
  update check).

## Supported versions

Only the latest release receives fixes.
