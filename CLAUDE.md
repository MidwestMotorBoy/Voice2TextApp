# Family Dictation

Wispr Flow-style dictation for the family: talk, get clean polished text typed into any app.
Android keyboard + iPhone app, both calling one Cloudflare Worker that holds the real API keys.

Full plan: `docs/plan.md`. Read it before starting a new phase.

## Layout

- `worker/` — Cloudflare Worker (`POST /dictate`): token check → Grok speech-to-text → Claude Haiku cleanup → clean text
- `android/` — Kotlin keyboard app (InputMethodService) with one big mic button, plus a setup Activity. No third-party libraries. Records and uploads from the keyboard itself (no app handoff like iOS).
- `ios/` — SwiftUI app (`FamilyDictation.xcodeproj`): record button + "Dictate" App Intent (Stage 1), and a keyboard extension `DictateKeyboard/` that hands off to the app through an App Group (Stage 2). `Shared/` is compiled into both; `Config/` holds plists, entitlements and `Base.xcconfig`.

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
- iPhone Stage 1 builds and its unit tests pass on the iOS Simulator (2026-11-27). The owner ran it on
  a real iPhone the same day and confirmed dictation works. The Action Button is still unverified.
- The committed Xcode project has no signing team and only placeholder identifiers
  (`com.example.familydictation`, `group.com.example.familydictation`) in `ios/Config/Base.xcconfig`.
  Real team ID, bundle id and App Group id go in `ios/Local.xcconfig` (gitignored). Never set them in
  Xcode's Signing tab and never write them in code: the App Group id is read from Info.plist.
- iPhone Stage 2 (keyboard) builds and its unit tests pass on the iOS Simulator (2026-11-27). The owner
  confirmed on a real iPhone (iOS 27.2) that the keyboard mic opens the app.
- The app keeps a 10-minute background "session" (microphone on standby, audio discarded) so later
  keyboard taps start a dictation without opening the app. Verified in the Simulator only; the
  Simulator does not enforce background limits, so this still needs confirming on a real iPhone.
- Android keyboard builds and its unit tests pass (2026-11-27). It has never been run on a phone or
  emulator. The committed applicationId is the placeholder `com.example.familydictation`; a real one
  goes in `android/local.properties` (`appId=`, gitignored). Family APKs are debug-signed on the
  owner's Mac, and updates must be signed with that same key.

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

iPhone (from `ios/`):
- `open FamilyDictation.xcodeproj` — open in Xcode; see `ios/README.md` for running on a phone
- `xcodebuild -project FamilyDictation.xcodeproj -scheme FamilyDictation -destination 'platform=iOS Simulator,name=iPhone 17' test` — build and run unit tests
- `xcodebuild -project FamilyDictation.xcodeproj -scheme FamilyDictation -destination 'generic/platform=iOS' -allowProvisioningUpdates build` — signed build for a phone (needs `ios/Local.xcconfig`)

Android (from `android/`; needs JDK 17 and `sdk.dir` in `android/local.properties`):
- `./gradlew test assembleDebug` — unit tests and the debug APK (`app/build/outputs/apk/debug/`)
