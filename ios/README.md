# iPhone app

Stage 1 and Stage 2 are built: a record button with the result copied to the clipboard, a "Dictate"
App Intent for the Action Button, and a Dictate keyboard that types the result into any app.
See "iPhone app" in `../docs/plan.md`.

## How the keyboard works

iOS keyboards are not allowed to use the microphone, so the keyboard and the app work together:

1. Tap the mic on the Dictate keyboard. The Dictate app opens and starts listening.
2. Swipe back to the app you were typing in. Dictate keeps listening in the background.
3. Tap stop on the keyboard. The app sends the audio, and the keyboard types the clean text.

The two halves talk through a shared App Group folder (`Shared/Handoff.swift`). The keyboard needs
**Allow Full Access** for that, and says so on screen if it is off. The keyboard never sees the token.

## What's here

- `FamilyDictation.xcodeproj` — the Xcode project (SwiftUI + a UIKit keyboard, iOS 17+, no third-party packages)
- `FamilyDictation/` — the app
  - `MainView.swift` — record button, "Listening…" / "Cleaning up…" states, result with Share
  - `SetupView.swift` — Worker address, family token, microphone permission
  - `DictationModel.swift` — the state machine: record → send → clipboard, and the keyboard handoff
  - `Recorder.swift` — `AVAudioRecorder` to a temp `.m4a` (AAC, 16 kHz, mono, ~32 kbps)
  - `DictationClient.swift` — the one `POST /dictate` call and its plain-language errors
  - `Settings.swift` — token in the Keychain, address in UserDefaults
  - `DictateIntent.swift` — the "Dictate" App Intent and shortcut
- `DictateKeyboard/` — the keyboard extension: mic button, globe, space, backspace, return
- `Shared/` — code compiled into both: the App Group handoff between keyboard and app
- `Config/` — Info.plist additions, entitlements, and `Base.xcconfig` with placeholder identifiers
- `FamilyDictationTests/` — unit tests for the network client and the handoff (no network needed)

Nothing personal is in the project: no Worker address, no token, no signing team, and only placeholder
identifiers (`com.example.familydictation`). Each person types the address and their token into the
setup screen. Keep it that way; this repo is public.

## Run it on your own iPhone

The keyboard needs an App Group, so real identifiers and a signing team are required. They go in a
file that git ignores, not in the project.

1. Copy `ios/Config/Local.xcconfig.example` to `ios/Local.xcconfig` and fill in your team ID, a bundle id
   unique to you, and the matching `group.` id. `ios/Local.xcconfig` is gitignored.
2. Open `ios/FamilyDictation.xcodeproj` in Xcode. Under Settings → Accounts, make sure your Apple ID is
   signed in so Xcode can create the signing profiles.
3. Plug in the iPhone, unlock it, and choose it as the run destination. The first time, the phone asks
   you to trust the Mac and to turn on Developer Mode (Settings → Privacy & Security → Developer Mode).
4. Press Run (⌘R). Or from `ios/`:
   `xcodebuild -project FamilyDictation.xcodeproj -scheme FamilyDictation -destination 'generic/platform=iOS' -allowProvisioningUpdates build`
5. In the app's setup screen, enter the Worker address and your family token, and allow the microphone.
6. Add the keyboard: Settings → General → Keyboard → Keyboards → Add New Keyboard → **Dictate**.
   Then tap **Dictate** in that list and turn on **Allow Full Access**.

Do not change the Team or Bundle Identifier in Xcode's Signing tab: that writes them into the project
file. Before committing anything under `ios/`, run `git diff` and check that no team ID or real
identifier appears.

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

Real microphone quality, the Action Button, opening the app from the keyboard, and recording in the
background after swiping away all need a physical iPhone.

## Fragile parts to re-test after each iOS update

- **Opening the app from the keyboard.** Apple gives keyboards no public way to open another app.
  `KeyboardViewController.openApp()` walks up to the application object and calls its open-URL method.
  If a future iOS blocks this, the keyboard shows "Couldn't start. Open the Dictate app once, then try
  again." after 5 seconds.
- **Recording in the background.** Relies on the `audio` background mode and an active audio session.
- **The handoff.** If the app is closed mid-dictation, the keyboard gives up after 10 seconds (stop not
  answered) or 90 seconds (cleanup not finished) rather than spinning forever.
