# Family Dictation

Talk, get clean text typed into any app. A private Wispr Flow-style setup for the family, about $1–2/month per heavy user.

```
phone (audio + family token) → Cloudflare Worker → Grok speech-to-text → Claude Haiku cleanup → clean text
```

- `worker/` — the proxy. Start here.
- `android/` — keyboard app (planned)
- `ios/` — iPhone app (planned)
- `docs/plan.md` — full design, costs, build order

## Quick start (Worker)

```bash
cd worker
npm install
cp .dev.vars.example .dev.vars   # fill in real keys
npx wrangler dev
scripts/test-dictate.sh ~/some-voice-memo.m4a
```

Deploy: create the KV namespace, put the three secrets, `npx wrangler deploy`. Details in `docs/plan.md`.
