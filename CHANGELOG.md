# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- **The second model in the auto-pick chain is now `qwen/qwen3.8-27b`.** Groq announced the
  deprecation of `qwen/qwen3.6-27b` on 1 September 2026 and switches it off on the 14th. Nothing
  would have broken: the app picks its chat model from the live list and heals itself when one
  disappears. But the second link would have quietly emptied, and anyone whose organisation
  blocks `openai/gpt-oss-120b` would have dropped straight to the 20b model. A manual choice of
  the retired model now falls back to "auto" as well, without waiting for the first live list.
- **Choosing "Local (offline)" now sticks.** Cancelling the model download, a failed download or
  deleting the model no longer flips the engine back to the cloud. Picking the local engine is a
  decision about privacy, not a preference about quality, and it is not the app's to reverse —
  even visibly. Without a model the dictation refuses at the start and says what is missing,
  which is enough. (Matches the Windows port, which never did the flip.)

### Fixed
- **The settings window no longer widens when the model download starts.** Keeping the button
  still required a fixed-width status text, and text plus button plus progress bar stopped
  fitting the tab — so the fix for one twitch caused another. The progress bar now has a row of
  its own.
- **The button next to the status line no longer moves out from under the cursor.** The status
  text changes at exactly the moment someone is about to press the button beside it — "Model not
  downloaded yet (400 MB)" becomes "Downloading model… 22%" — and the button used to slide left
  along with it. The text now keeps its place, and "Download" and "Cancel" occupy the same spot.
- **"Delete all data" now says when a key survives it.** The saved key is deleted, but a key set
  in the `GROQ_API_KEY` environment variable keeps working, and a filled-in key field next to
  "everything deleted" reads like the deletion failed. Environment variables are a system setting
  and not the app's to change, so the app now names the variable instead of staying quiet.

## [0.9.19] — 2026-08-26 — Voica gets out through a corporate proxy

### Added
- **Voica works behind a corporate proxy.** The app already followed the system proxy — that
  part never needed code. What was missing is authentication: the proxy answers `407`, nothing
  supplies credentials, and from the outside it looks like the app cannot do proxies at all.
  All three network calls — Groq, the model download and the update check — now go through one
  place that can answer the proxy's challenge with the credentials the system already holds.
  Nothing to type in Voica: macOS keeps the proxy password in System Settings → Network →
  Proxies, and asks for it there itself.
- **A Network tab in Settings**, before About, with a "Use the system proxy" switch (on by
  default). Turning it off makes requests go straight out, ignoring the system settings — a
  proxy configured wrongly gets in the way as often as a missing one helps.
- **A proxy failure now says so, and names the proxy**, instead of a generic network error —
  everywhere it can surface: dictation, the key's Test button, the update check and the model
  download. The Network tab also shows which proxy the app is actually using, so "did my setting
  take effect?" has an answer on screen rather than in a log.
  The log records which proxy the system picked for the address, because without it a diagnosis
  in someone else's network turns into an exchange of letters.

### Fixed
- **"Local (offline)" no longer sends a dictation to the cloud behind your back.** With the
  local engine selected but no model on disk, the recording went to Groq while the switch still
  said offline. The cloud never stands in for a missing model now — not even while the model is
  downloading, since agreeing to a download is not agreeing to send your voice out. Instead the
  warning comes up *before* recording starts, names what is missing, and offers a button
  straight to the tab where the model is downloaded. Found by deleting the model and dictating —
  the history entry said `whisper-large-v3`.

- **Dictating with no Groq key now says so, instead of nothing happening.** With cloud
  recognition selected and no key, a short press produced a blink of the recording capsule and
  silence — the recording was below the "accidental press" threshold and was dropped without a
  word. The check now happens before recording starts, the same way it does for a missing local
  model, and offers the way out: paste a key, or switch to the local engine.
- **Two identical warnings no longer stack on top of each other.** In push-to-talk mode — the
  macOS default — every press starts a dictation, so two presses produced two copies of the same
  window. The second one now just brings the first to the front.
- **Voica comes back with Cmd+Tab after the settings window was opened from a warning.** The
  app is a menu-bar agent and only joins the app switcher while a window is open; it used to
  join *after* activating, so the switcher had no record of it being used and put it last in the
  list. It now joins first and activates second.

### Changed
- **Switching to the local engine no longer starts a 400 MB download on its own.** There is a
  "Download model" button instead. In a network where the proxy wants authentication, the old
  behaviour meant an instant failure nobody asked for.

## [0.9.18] — 2026-08-22 — Text cleanup follows what was actually said

### Fixed
- **A filler in the middle of the text no longer leaves the next sentence in lower case.**
  The rule only looked at the very start of the text, so "…they took him outside. uh, to work
  then" kept "to" in lower case. The sentence boundary is decided by the separator that
  survives the removal — there are two around a filler and only one is kept — and the case of
  the filler itself now counts only at the start of the text. Mid-text it lies: the recogniser
  writes a filler capitalised as a remark of its own, and "closed them, Hmm, then decided"
  would have become "closed them, Then decided".
- **"Угу", "ага" and "мхм" were listed as fillers but could never fire** — the length gate lets
  through forms of up to two letters, and all three are three. Found by mirroring against the
  Windows port. They are not being resurrected: these are words of agreement, they carry
  meaning unlike mumbling, and a dictation consisting of a single "Ага." would have come out
  empty. The list now holds only what it can actually remove.

- **A chunk with no words could crash the local engine.** A string of spaces is not empty but
  splits into zero words, and the fallback overlap search then walked a range from one to zero —
  in Swift that is a trap, not an exception, so the app would have gone down rather than
  recovered. The decoder trims its output today, which is why nobody ever hit it; the guard now
  sits where the break happens instead of where luck holds.

- **The "Active model" line no longer names a model you did not pick.** The cloud wording had
  `whisper-large-v3-turbo` baked into the translated string, so it kept claiming turbo while the
  setting said `whisper-large-v3`. It now reads the setting, and it updates the moment you change
  the model rather than at the next opening of Settings.

### Changed
- **Terms written in plain Latin are matched a little more freely** — letter similarity of 0.5
  instead of 0.6, on top of the exact consonant skeleton that was always required. A live miss
  prompted it: the engine wrote `Depsic`, the skeleton matched `DeepSeek` exactly, and the
  similarity came out at exactly 0.50. Running the whole history (138 lines, texts and raw)
  at 0.5 changed not a single line against 0.6 — twenty replacements either way — and the traps
  hold: "Greek" is kept away from "Groq" by the skeleton, not by the threshold.
- **The local engine hint no longer says the vocabulary is cloud-only.** Rules fix terms on
  both engines, without a key or a network, and that is where they help most.

## [0.9.17] — 2026-08-20 — The capsule now shows what the microphone hears

### Added
- **Filler sounds can be stripped from the text** — the drawn-out "uh", "um" and "hmm" that mean
  nothing in speech but clutter the page. On by default; there is a checkbox in Settings →
  Dictation, because removing them is removing something you actually said, and anyone
  transcribing speech verbatim will want it off. Works by rules, offline, on both engines.
  A word that was merely drawn out is straightened rather than dropped: "ну-у-у" becomes "ну",
  since throwing it away would lose meaning. Ordinary speech is left alone — single "а", "и",
  "у" and "о" are conjunctions and prepositions, numbers and all-caps abbreviations are never
  touched. A filler at the start of a sentence leaves the next word capitalised, so the text
  doesn't begin in lower case.
- **Quotes are tidied up.** The recogniser writes them however it happens to: guillemets and
  straight quotes turn up in the same sentence, one side of a pair goes missing, and the space
  after a colon disappears. Straight quotes now become proper Russian guillemets based on where
  they sit (English text is left alone), the missing space is restored, and a quote left without
  its pair is removed. When a closing quote is missing, which one to drop depends on meaning:
  "Да", это стопроцентный вариант" was one phrase in quotes, not one word, so the early closing
  goes and you get «Да, это стопроцентный вариант». A closing followed by a full stop is a real
  one and stays put. Both the recogniser and the language model can
  leave one behind — the local engine decodes frame by frame with no memory that a quote is
  already open, and the model likes to wrap a substituted term in quotes despite being told not
  to, often on one side only. Since there is no telling which of them did it, the check runs last,
  after both. Matched pairs are left alone.

### Fixed
- **One more kind of doubling in long dictations.** Recordings are stitched from 25-second
  windows, and neighbouring windows sometimes split the same spot into a different number of
  words — one heard "3кар", the next "Три кар". Word-by-word comparison cannot line those up at
  all, so the phrase was written twice. Voica now falls back to comparing the joined text when
  the word-by-word pass finds nothing.

### Changed
- **The wave in the recording capsule follows your actual voice** instead of running the same
  animation regardless. This is not decoration: with a fixed animation, a microphone held by
  another app, the wrong input selected, or simply sitting too far away all look exactly like a
  normal recording — and you find out something was wrong only from the empty text at the end.
  Now the wave rises on speech and settles in pauses, so cover the microphone and you will see
  it go flat. The level comes from the system's own loudness reading rather than arithmetic over
  raw samples — that arithmetic is what cost a Windows user six minutes of speech, and in Swift
  it would crash the app outright. In silence the wave quiets down but never freezes: a dead flat
  line reads as a hung application. Windows has worked this way since 0.6.0.

## [0.9.16] — 2026-08-20 — Nothing said is quietly lost

Both fixes come from the Windows port, found on real dictations. Both existed here too — one
was losing text on every long recording, the other had simply not happened to us yet.

### Fixed
- **Long dictations lost fewer repeated fragments still.** A run of overlapping words was only
  accepted if every word matched, so a single divergence broke it — "управляющий" against
  "управляющего" is 9 letters out of 12, just under the threshold, and the whole phrase went
  into the text twice. A run of four words or more now forgives one mismatch. The forgiven word
  can never be the last one in the run: a divergence right at the seam is usually a word cut in
  half by the window edge, and that has to be dropped rather than forgiven. The threshold itself
  was left alone — lowering it would have been fitting one case instead of fixing the cause.
  Re-checked on the same six-minute recording used before: six more doubled fragments gone,
  nothing else touched.

### Added
- **Voica notices when the microphone stops sending audio, and keeps what was recorded.** Until
  now a capture failure mid-dictation was invisible: the state stayed "recording", the capsule
  kept animating, and nothing more reached the file. You would find out at the end, from a text
  that stopped halfway, with nothing left to repeat. On Windows this ate six minutes of speech
  out of six and a half. Voica now watches the recording clock — it keeps advancing while
  recording and freezes when capture dies, and audio keeps arriving even in complete silence, so
  a three-second pause means failure rather than a quiet speaker. The dictation ends at once, you
  are told the microphone went quiet, and everything recorded before that is transcribed.

## [0.9.15] — 2026-08-19 — Terms are fixed by rules, before any AI

Until now the vocabulary did nothing at all on the local engine: the recognition hint is a cloud
Whisper feature, and only the cloud language model could fix a mangled term. Offline mode was
only half offline.

### Added
- **Terms are now fixed by rules, on your own machine.** No download, no memory, no network, no
  API key — and it works on both engines. It runs before the AI pass and switches itself on
  whenever the vocabulary isn't empty; there is no separate checkbox, because you filled in the
  vocabulary precisely so those words come out right.
  A garbled term is recognised by its consonant skeleton — vowels are what recognition loses and
  confuses, consonants survive. Every real-world mangling of `DeepSeek` seen in testing —
  `Dпсик`, `Dпсиcк`, `Deepsc`, `диппсих` — maps to the same skeleton as the term itself. Words
  mixing Latin and Cyrillic letters (`Dпсик`, `раadio`) are a reliable sign of a mangled foreign
  name: ordinary Russian text never looks like that.
  Compound terms are matched across up to two words, because recognition both glues them together
  (`клодкод`) and splits them apart (`Tail scale`).
  Rules deliberately stay quiet when unsure. A missed term is picked up by the AI pass if you have
  it on; a word replaced by mistake would go unnoticed, which is worse. Checked against the whole
  history: 60 dictations, 20 replacements, every one of them correct.
- **Full offline mode.** Local engine plus the AI toggle off — neither audio nor text leaves your
  Mac, and terms are still corrected.
- **Search in History** (Cmd+F, or the field above the list). It searches the finished text *and*
  what recognition heard before any fixing — you remember what you said, not what it was turned
  into. Matches are highlighted, the text scrolls to the first one, and the number of matches in
  the selected entry is shown. If the match was in the original wording, that original appears
  below the text with the match highlighted.

### Fixed
- **Long dictations no longer contain doubled fragments.** Recordings are recognised in 25-second
  windows and stitched back together; the seam was matched word-for-word, but neighbouring windows
  hear the overlap differently ("руководителя" / "руководитель"), so no overlap was found and both
  copies ended up in the text. Words are now compared leniently, and a word cut in half by the
  window edge no longer breaks the comparison. Verified on a real six-minute recording: three
  doubled fragments gone, nothing else touched.
- **`allam-2-7b` is no longer offered as a chat model** — see 0.9.14; it stays out because the
  live list is sorted alphabetically and it silently became the fallback for Russian terms.

### Changed
- **The vocabulary and AI hints in Settings were rewritten.** They said the vocabulary only worked
  with the cloud engine and that the AI pass was the way to fix terms. Both stopped being true.
- **History keeps the text as recognition produced it**, whenever fixing changed something. It is
  what makes it possible to tell an engine mistake from a model mistake — and it is what search
  looks through. Same retention and same "delete all data" as everything else.

## [0.9.14] — 2026-08-19 — Reasoning models no longer leak their thinking

### Fixed
- **Some chat models pasted their own reasoning instead of your dictation.** Newer models return
  their train of thought in the reply, wrapped in `<think>…</think>`, with the answer after it —
  and Voica inserted the lot. This was not exotic: `qwen/qwen3.6-27b` is the second link in the
  default model chain, so anyone whose `openai/gpt-oss-120b` is blocked hit it on every dictation.
  Reasoning blocks are now stripped before the text reaches you. Reported by a user.
- **A second guard against nonsense.** Fixing terms swaps individual words, so the reply can't be
  wildly longer than what you dictated. If it is — or if nothing is left after stripping — Voica
  falls back to the raw text, the same way it already does on any error. This catches chatty
  models in general, not just the `<think>` format.
- **The self-test no longer depends on the machine it runs on.** The check for "in auto mode the
  active model equals the seed" read the real resolved-model cache, so it failed on any machine
  where a model had been picked by hand. It passed on CI only because settings there are pristine.

### Changed
- **`allam-2-7b` is no longer offered as a chat model.** Nothing wrong with it — but the live model
  list is sorted alphabetically and `allam` lands first, which quietly made an Arabic-tuned model
  the fallback for correcting Russian terms. It can come back the day someone actually dictates
  in Arabic.
- **The language hint now says auto-detect covers around a hundred languages.** The picker offers
  auto, ru and en, which read like the full list of what Voica understands. It isn't: everything
  goes through auto-detect, and forcing ru or en only helps short phrases it gets wrong.

## [0.9.13] — 2026-08-14 — Blocked-model notification

### Added
- **A notification when the chat model is blocked.** If the model isn't enabled for your Groq
  organisation, the API answers 403 — the model is alive, so self-healing can't help. Until now
  term correction just stopped working silently on every dictation. Voica now tells you once per
  session which model was refused and where to enable it (console.groq.com → Settings → Limits).

### Changed
- **`groq/compound` and `groq/compound-mini` no longer show up in the model picker.** They aren't
  chat models but agentic systems with their own routing and tools — an extra layer for a single
  short term fix, and they route to models your organisation may not have.

## [0.9.12] — 2026-08-14 — Chat model chain refreshed

Groq is retiring `llama-3.3-70b-versatile` on 16 August 2026. Voica heals itself when a model
disappears — a 404 during AI term correction triggers a background re-resolve, and the dictation
itself is never blocked — so nothing breaks without this update. It removes the dead model from
the defaults so a fresh install doesn't start by talking to it.

### Changed
- **Model priority chain** for “Fix terms with AI” is now `openai/gpt-oss-120b` →
  `qwen/qwen3.6-27b` → `openai/gpt-oss-20b` → `llama-3.1-8b-instant` — both models Groq named as
  replacements are in it. The default seed (first launch, offline) moved to `openai/gpt-oss-120b`.
- `llama-3.3-70b-versatile` joins the retired list: a saved manual pick, and a cached resolved
  model, migrate to “recommended (automatic)” instead of costing one failed request per launch.
- Dropped `gemma2-9b-it` from the chain — Groq stopped serving it some time ago, unannounced.

Nothing to do on your side: if you had picked a specific model by hand, it will switch back to
automatic and the status line in Settings will show what it resolved to.

## [0.9.11] — 2026-08-08 — Settings window sizing

### Fixed
- **Settings opened too tall when it opened straight on About** (the menu-bar “About Voica”
  item). The tab was selected before the window had ever been on screen, so the window kept the
  height of a different tab.
- **The Settings window never shrank back.** It grew for a taller tab and stayed that way, so
  shorter tabs were shown with dead space at the bottom. Present since 0.8.0, when the tabs were
  introduced; it only became visible in 0.9.10, once About grew a Support button and became the
  tallest tab.

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

