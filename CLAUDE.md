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

## Status

- Worker is deployed and verified end to end on 2026-11-27 with real keys: Grok transcribes
  (`POST /v1/stt`, multipart, `file` last, no `model` field, Bearer auth) and Claude cleans up.
- Grok already strips "um"/"uh" by default; Claude handles self-corrections and the rest.
- The Worker URL contains the owner's name, so it is kept out of this public repo. Apps take the URL
  and the family token at setup time rather than hard-coding them.
- Family tokens live in the `FAMILY_TOKENS` Worker secret and in `worker/family-tokens.local.json`
  (gitignored) on the owner's Mac.

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
