# Family Dictation App: Proxy + App Plan

Original doc: https://claude.ai/artifact/Pe6ZWA8xfSYK2AGzbLCm6g (Nov 27, 2026)

## Overview

A Wispr Flow-style dictation app for the family, on Android and iPhone, running on one shared Grok + Claude bill of roughly $1–2 a month even with heavy use. The person talks, the app turns it into clean, polished text, and the text lands in whatever box they're typing in.

The key design choice is a **small proxy server** that holds the real API keys. The apps never see the Grok or Anthropic keys. Each family member gets their own token instead, so you can:

- Cap each person's monthly usage
- Cut one person off (lost phone, leaked token) without touching anyone else
- Swap or rotate the real keys in one place, with no app update

Putting the real keys on each phone, even entered separately from the app, would leave them extractable, and a leak would mean changing every device.

## Architecture

The phone makes one call and gets clean text back. Everything else happens on the Worker.

```
Family phone                 Cloudflare Worker                     Grok speech-to-text
(Android keyboard   audio    1. Check token + monthly cap   <--->  audio -> raw transcript
 or iPhone app)    ------>   2. Audio to Grok                       $0.10 / hour
                   <------   3. Transcript to Claude        <--->  Claude Haiku
                 clean text  4. Add usage seconds                   raw -> clean text
                             Holds both real API keys               < $1 / month
```

If Claude fails, the raw transcript comes back instead, so the person still gets their words.

## Cloudflare Worker

One endpoint, `POST /dictate`, about 80 lines (`worker/src/index.js`). Fits Cloudflare's free tier at family scale.

### Setup

1. `cd worker && npm install && npx wrangler login`
2. `npx wrangler kv namespace create USAGE`, then paste the id into `wrangler.toml`
3. Make one token per person: `openssl rand -hex 24`
4. Store the secrets:
    - `npx wrangler secret put XAI_API_KEY`
    - `npx wrangler secret put ANTHROPIC_API_KEY`
    - `npx wrangler secret put FAMILY_TOKENS` — JSON map of token to person (below)
5. `npx wrangler deploy` → `https://family-dictation.<you>.workers.dev`

```json
{
  "9f3c...a1": { "name": "dad", "capSeconds": 36000 },
  "4be0...7d": { "name": "mom", "capSeconds": 36000 }
}
```

`capSeconds: 36000` = 10 hours of audio a month, about $1 of Grok. To cut someone off, delete their entry and re-run `wrangler secret put FAMILY_TOKENS`.

### API contract

Request:

```
POST /dictate[?cleanup=0]
Authorization: Bearer <family token>
Content-Type: audio/mp4
X-Duration-Seconds: <int>
<body: raw .m4a bytes, max 10 MB>
```

Response: `{"text": "<clean>", "raw": "<transcript>"}`. Errors: 401 unauthorized, 413 bad size, 429 monthly limit, 502 transcription failed.

The usage cap trusts the duration the app reports, which is fine for family.

## Android app

Build it as a **custom keyboard (IME)** with one big mic button rather than a floating accessibility bubble. A keyboard types into any app directly, skips the accessibility permission hurdles, and one big button is easier for Dad.

| Part | What it does | Android API |
| --- | --- | --- |
| Keyboard service | Shows the mic button, inserts the result | `InputMethodService`, `currentInputConnection.commitText()` |
| Recorder | Records to a temp `.m4a` | `MediaRecorder` (AAC in MPEG-4, 16 kHz mono, ~32 kbps) |
| Network call | POSTs audio + token to the Worker, reads `text` | OkHttp on a coroutine |
| Setup screen | Paste token, mic permission, link to keyboard settings | `Activity` + SharedPreferences |
| Fallback keys | Switch keyboard, backspace, space, enter | `switchToNextInputMethod()`, `sendKeyEvent()` |

Core of the keyboard:

```kotlin
private fun onMicReleased(file: File, seconds: Int) {
    showStatus("Cleaning up…")
    scope.launch {
        val text = withContext(Dispatchers.IO) {
            val req = Request.Builder()
                .url("$WORKER_URL/dictate")
                .header("Authorization", "Bearer ${prefs.token}")
                .header("X-Duration-Seconds", seconds.toString())
                .post(file.asRequestBody("audio/mp4".toMediaType()))
                .build()
            client.newCall(req).execute().use { res ->
                if (!res.isSuccessful) null
                else JSONObject(res.body!!.string()).optString("text")
            }
        }
        if (text.isNullOrBlank()) showStatus("Didn't catch that — try again")
        else currentInputConnection?.commitText("$text ", 1)
        file.delete()
    }
}
```

Things to get right:

- **Mic permission.** A keyboard can't show the permission prompt itself, so the setup screen asks for `RECORD_AUDIO` once.
- **Button behavior.** Tap to start, tap to stop (easier than holding). Clear "Listening…" state, 3–5 minute auto-stop.
- **Token storage.** Private SharedPreferences is fine; the token is capped and revocable.
- **Errors.** Plain messages on the keyboard ("No internet", "Monthly limit reached"). Never leave it spinning.

Installing on Dad's Samsung:

1. Build the APK (Android Studio or `./gradlew assembleRelease`) and copy it to his phone.
2. If **Auto Blocker** refuses the install, turn it off under Settings → Security and privacy, install, turn it back on.
3. Open the app, paste his token, allow the microphone.
4. Enable the keyboard under Settings → General management → Keyboard list and default. If greyed out: Settings → Apps → the app → ⋮ → **Allow restricted settings**.
5. Switch keyboards with the keyboard icon in the navigation bar, or set it as default.

Sideloaded apps don't auto-update: reinstall a newer APK, or use Obtainium pointed at a private GitHub release.

## iPhone app

Harder because **iOS keyboards can't use the microphone**. Build in two stages.

### Stage 1: main app + Action Button

- One screen with a big record button (`AVAudioRecorder`, AAC `.m4a`).
- POST to the same Worker with `URLSession`, same headers as Android.
- Copy the clean text to the clipboard; show it with a Share button.
- An **App Intent** "Dictate" so iPhone 15 Pro+ users can put it on the **Action Button** or Control Center: press, talk, press, paste.

### Stage 2: keyboard extension

1. Keyboard extension with a mic button; needs **Allow Full Access**.
2. Tapping the mic opens the main app, which starts recording with background audio; the person swipes back.
3. When they tap stop on the keyboard, the app sends the audio and writes the result to a shared **App Group** container.
4. The keyboard inserts it with `textDocumentProxy.insertText()`.

This handoff is the fiddly part. Test it on every iOS update.

### Distribution (TestFlight)

- $99/yr Apple Developer account, unlimited apps.
- Family as **internal testers** (users in App Store Connect): no beta review, up to 100.
- **Xcode Cloud** workflow on a schedule (every 2–4 weeks): build, bump build number, upload to TestFlight. Builds expire after 90 days. 25 compute hours/month included.
- Each person turns on **Automatic Updates** in TestFlight once.
- Watch email for new Apple agreements; uploads stop until accepted.

## Costs

| Item | Cost | Notes |
| --- | --- | --- |
| Grok speech-to-text | $0.10 / hour of audio | 20 min/day ≈ 10 h/month ≈ $1 ([xAI pricing](https://docs.x.ai/developers/pricing)) |
| Claude Haiku cleanup | < $1 / month per person | Short texts |
| Cloudflare Worker + KV | $0 | Free tier |
| Apple Developer Program | $99 / year | iPhone only |
| Android | $0 | Sideloaded APK |

## Security checklist

- Real keys only in Worker secrets, never in apps or git.
- One token per person.
- Monthly spend limits in the xAI and Anthropic consoles as a backstop.
- No audio or text logged; only usage seconds stored.
- Cleanup prompt treats the transcript as data.

## Build order

- [ ] Worker: verify xAI STT format, run with `wrangler dev`, test with a real `.m4a`, deploy
- [ ] Tune the cleanup prompt on real voice memos from Dad
- [ ] Android keyboard v1 on Dad's Samsung
- [ ] iPhone Stage 1 (main app + Action Button)
- [ ] iPhone Stage 2 (keyboard extension), if Stage 1 feels clunky
- [ ] Xcode Cloud scheduled TestFlight builds

## Open questions

- xAI STT request format (path, `file` field, model name): https://docs.x.ai/developers/rest-api-reference/inference/voice
- Which family members are on iPhone, and which models? Decides whether the Action Button path covers them.
