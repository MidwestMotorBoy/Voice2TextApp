# Android keyboard

A custom keyboard with one big mic button: tap to start, tap to stop, and the cleaned-up text is typed
into whatever box is open. Unlike iPhone, an Android keyboard may use the microphone itself, so there
is no app to open and nothing to swipe back from. See "Android app" in `../docs/plan.md`.

Built and unit-tested, but not yet run on a phone or emulator.

## What's here

- `app/src/main/java/com/example/familydictation/`
  - `DictateKeyboardService.kt` — the keyboard: mic button, "Listening…" / "Cleaning up…" states,
    5-minute auto-stop, plus switch-keyboard, space, delete and enter
  - `Recorder.kt` — `MediaRecorder` to a temp `.m4a` in the cache (AAC, 16 kHz, mono, ~32 kbps)
  - `DictationClient.kt` — the one `POST /dictate` call and its plain-language errors
  - `SetupActivity.kt` — Worker address, family token, microphone permission, turning the keyboard on
  - `Settings.kt` — address and token in the app's private storage
- `app/src/test/` — unit tests for the network client against a local stub server (no network needed)

Kotlin, no third-party libraries, Android 10 (API 29) and newer.

Nothing personal is in the project: no Worker address, no token, no keystore. Each person types the
address and their token into the setup screen. Keep it that way; this repo is public.

## Build

You need JDK 17 and the Android SDK (platform 35, build-tools 35). Tell Gradle where the SDK is, in
`android/local.properties` (gitignored):

```
sdk.dir=/path/to/android/sdk
# optional: your own application id instead of the placeholder com.example.familydictation
appId=com.yourname.familydictation
```

Then, from `android/`:

```bash
./gradlew test assembleDebug
```

The app file is `app/build/outputs/apk/debug/app-debug.apk`.

### Signing and updates

The debug build is signed with the debug key Android's tools create on the build machine
(`~/.android/debug.keystore`). Android only installs an update over an existing copy if it is signed
with the **same key**, so:

- Always build family updates on the same Mac, or keep a copy of that keystore somewhere safe.
- If a proper release keystore is created later, keep it safe and **out of git** (`*.keystore` and
  `*.jks` are gitignored). Switching keys means everyone uninstalls and reinstalls once.

## Install on a Samsung phone

1. Get the `.apk` file onto the phone (email it, Google Drive, or a USB cable) and tap it.
2. Allow the install when Android asks ("Install unknown apps" for the app you opened it from).
   If **Auto Blocker** refuses it: Settings → Security and privacy → Auto Blocker → off, install, then
   turn it back on.
3. Open **Dictate**. Enter the Worker address and the person's family token, and tap **Save**.
4. Tap **1. Allow microphone** and choose "While using the app".
5. Tap **2. Turn on the Dictate keyboard** and switch Dictate on in the list. If the switch is greyed
   out: Settings → Apps → Dictate → ⋮ (top right) → **Allow restricted settings**, then try again.
6. Tap **3. Switch to the Dictate keyboard**, pick Dictate, and try it in the "Try it here" box.

Day to day: switch to Dictate with the keyboard icon in the navigation bar. The ⌨ key on the Dictate
keyboard goes back to the previous keyboard (hold it to choose from the list).

Sideloaded apps don't update themselves: install a newer `.apk` over the old one.

## Not verified yet

- Running on a real phone or emulator at all: recording from the keyboard, the text being typed in,
  the look of the keyboard, and Samsung's install prompts.
- "No internet" is decided by Android's network status before sending; a wrong Worker address shows
  "Didn't work, try again".
- If the keyboard is hidden while listening, the recording is discarded rather than sent.
