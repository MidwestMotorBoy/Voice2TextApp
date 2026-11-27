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

- xAI speech-to-text REST request format: path (`/v1/stt`?), multipart field name (`file`?), model name.
  Check https://docs.x.ai/developers/rest-api-reference/inference/voice before relying on `worker/src/index.js`.
- The Worker code in this repo was written but never run. Treat it as a draft to test.

## Working style

- One phase at a time: Worker → Android keyboard → iPhone Stage 1 → iPhone keyboard extension.
- Each phase ends with something testable on a real device or via curl.

## Commands

Worker (from `worker/`):
- `npm install` — installs wrangler locally
- `npx wrangler dev` — run locally (put test secrets in `worker/.dev.vars`, gitignored)
- `scripts/test-dictate.sh <audio.m4a>` — POST a recording to the Worker
- `npx wrangler deploy` — deploy

Android (from `android/`, once it exists): `./gradlew assembleDebug`
