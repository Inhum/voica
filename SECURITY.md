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
- Voica has no backend, no telemetry, and makes no network calls other than to
  `api.groq.com`.

## Supported versions

Only the latest release receives fixes.
