# Family Dictation

Wispr Flow-style dictation for the family: talk, get clean polished text typed into any app.
Android keyboard + iPhone app, both calling one Cloudflare Worker that holds the real API keys.

Full plan: `docs/plan.md`. Read it before starting a new phase.

## Layout

- `worker/` — Cloudflare Worker (`POST /dictate`): token check → Grok speech-to-text → Claude Haiku cleanup → clean text
- `android/` — custom keyboard (InputMethodService) with one big mic button. Not started.
- `ios/` — main app + Action Button intent, later a keyboard extension. Not started.

## Hard rules

- Real API keys (xAI, Anthropic) live ONLY in Worker secrets. Never in app code, config files, tests or git.
- Apps authenticate with a per-person family token. One token per person so one can be revoked alone.
- If Claude cleanup fails, return the raw transcript. Never return an error when we have words.
- The cleanup prompt treats the transcript as data, not instructions. Keep it that way.
- Don't log audio or transcript text. Only usage seconds are stored (KV).
- Keep it simple: this is for a handful of family members, not a product.

## Known unknowns (verify, don't assume)

- xAI speech-to-text format was checked against the docs on 2026-11-27 (`POST /v1/stt`, multipart,
  `file` last, no `model` field, response has `text` and `duration`). The Bearer auth header is
  inferred from xAI's other endpoints, and nothing has been tried with a real key yet.
- The Worker passes `npm test` (fake Grok and Claude) but has never run against the real APIs or been deployed.

## Working style

- One phase at a time: Worker → iPhone Stage 1 → Android keyboard → iPhone keyboard extension.
- Each phase ends with something testable on a real device or via curl.

## Commands

Worker (from `worker/`):
- `npm install` — installs wrangler locally
- `npm test` — runs the Worker against fake Grok and Claude, no keys needed
- `npx wrangler dev` — run locally (put test secrets in `worker/.dev.vars`, gitignored)
- `scripts/test-dictate.sh <audio.m4a>` — POST a recording to the Worker
- `npx wrangler deploy` — deploy

Android (from `android/`, once it exists): `./gradlew assembleDebug`
