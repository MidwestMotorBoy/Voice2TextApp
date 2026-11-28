# iPhone app

Stage 1 is built: one big record button, the result copied to the clipboard, and a "Dictate" App Intent
for the Action Button. Stage 2 (keyboard extension) is not started. See "iPhone app" in `../docs/plan.md`.

## What's here

- `FamilyDictation.xcodeproj` — the Xcode project (SwiftUI, iOS 17+, no third-party packages)
- `FamilyDictation/` — the app
  - `MainView.swift` — record button, "Listening…" / "Cleaning up…" states, result with Share
  - `SetupView.swift` — Worker address, family token, microphone permission
  - `DictationModel.swift` — the state machine: record → send → copy to clipboard
  - `Recorder.swift` — `AVAudioRecorder` to a temp `.m4a` (AAC, 16 kHz, mono, ~32 kbps)
  - `DictationClient.swift` — the one `POST /dictate` call and its plain-language errors
  - `Settings.swift` — token in the Keychain, address in UserDefaults
  - `DictateIntent.swift` — the "Dictate" App Intent and shortcut
- `FamilyDictationTests/` — unit tests for the network client (stubbed, no network needed)

Nothing personal is in the project: no Worker address, no token, no signing team. Each person types the
address and their token into the setup screen. Keep it that way; this repo is public.

## Run it on your own iPhone

1. Open `ios/FamilyDictation.xcodeproj` in Xcode.
2. Click the blue **FamilyDictation** project at the top of the left sidebar, pick the **FamilyDictation**
   target, then the **Signing & Capabilities** tab.
3. Set **Team** to your own. A free Apple ID works: add it under Xcode → Settings → Accounts, then choose
   "Your Name (Personal Team)".
4. Change **Bundle Identifier** from `com.example.familydictation` to something unique to you, such as
   `com.yourname.familydictation`.
5. Plug in the iPhone, unlock it, and choose it as the run destination at the top of the Xcode window.
   The first time, the phone asks you to trust the Mac and to turn on Developer Mode
   (Settings → Privacy & Security → Developer Mode), which needs a restart.
6. Press Run (⌘R). With a free Apple ID the phone then refuses to open the app until you trust yourself:
   Settings → General → VPN & Device Management → your Apple ID → Trust.
7. In the app's setup screen, enter the Worker address and your family token, and allow the microphone.

Do not commit the Team or Bundle Identifier change. Before committing anything under `ios/`, run
`git diff` and check that `DEVELOPMENT_TEAM` is still empty and the bundle id is still the placeholder.

With a free Apple ID the app stops opening after 7 days; press Run again to renew it. A paid developer
account ($99/yr) lasts a year per install and allows TestFlight for the rest of the family.

## Put it on the Action Button

Settings → Action Button → swipe to **Shortcut** → choose **Dictate** under this app.
Press the button, talk, tap stop, then paste wherever you were typing.

## Build and test from the command line

From `ios/`:

```bash
xcodebuild -project FamilyDictation.xcodeproj -scheme FamilyDictation -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Use any simulator name that `xcrun simctl list devices available` shows.

## What the Simulator can't check

Real microphone quality, the Action Button, and behaviour when the phone locks mid-recording all need a
physical iPhone.
