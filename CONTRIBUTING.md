# Contributing to Voica

Thanks for your interest! Voica is a spare-time project, so please keep expectations
realistic: responses may be slow, and not every feature request will be accepted. That
said, bug reports and focused pull requests are very welcome.

## Reporting bugs & requesting features

Open an [issue](https://github.com/Inhum/voica/issues) using the templates. For bugs,
include your macOS version, Voica version (menu → About), and steps to reproduce.

## Development

Requirements: macOS 13+ and Command Line Tools (`xcode-select --install`). Full Xcode is
not needed — the app is built directly with `swiftc`.

```bash
git clone https://github.com/Inhum/voica.git
cd voica
./scripts/make-cert.sh   # once: local signing certificate (optional but recommended)
./scripts/run.sh         # build + run with logs in the terminal
```

Before opening a PR, make sure the self-test passes:

```bash
./scripts/build.sh
./build/Voica.app/Contents/MacOS/Voica --test-all
```

## Code style

- Match the surrounding code: same naming, comment density, and AppKit idioms.
- One file per component under `Sources/` (see existing structure).
- User-facing strings go through `L("key")` with entries added to **both**
  `Resources/en.lproj/Localizable.strings` and `Resources/ru.lproj/Localizable.strings`.
- Keep it dependency-free — the app uses only system frameworks.

## Pull requests

- Keep PRs focused; one concern per PR.
- Describe what changed and how you tested it.
- For anything user-facing, update the relevant docs and both `.strings` files.

## Scope

See [docs/ROADMAP.md](docs/ROADMAP.md) for planned directions and open questions before
proposing large features.
