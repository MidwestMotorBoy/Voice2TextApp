import Foundation
import Observation
import UIKit

/// The whole app's state: idle → listening → cleaning up → result or error.
/// Never logs audio or transcript text.
///
/// A dictation can be started in the app (button or Action Button), in which case the
/// result goes to the clipboard, or by the keyboard, in which case recording continues
/// in the background and the result is also handed back to the keyboard to type in.
@MainActor
@Observable
final class DictationModel {
    enum Phase { case idle, starting, listening, cleaningUp }

    static let shared = DictationModel()
    static let maxSeconds: Double = 5 * 60

    private(set) var phase: Phase = .idle
    private(set) var startedAt: Date?
    private(set) var resultText: String?
    private(set) var errorMessage: String?
    /// True while the current dictation was started from the keyboard.
    private(set) var keyboardSession = false
    var showSetup = false

    private let recorder = Recorder()
    private let client = DictationClient()
    private let handoff = HandoffStore.shared
    private var autoStop: Task<Void, Never>?
    private var stopWatcher: Task<Void, Never>?

    private init() {
        // Anything left over from a previous run of the app is no longer true.
        handoff?.clear()
        HandoffSignal.stopRequested.startListening()
        NotificationCenter.default.addObserver(
            forName: HandoffSignal.stopRequested.localName, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.checkStopRequest() }
        }
    }

    func toggle() async {
        switch phase {
        case .idle: await start()
        case .listening: await stopAndSend()
        case .starting, .cleaningUp: break
        }
    }

    func start(fromKeyboard: Bool = false) async {
        guard phase == .idle else { return }
        keyboardSession = fromKeyboard

        guard Settings.isConfigured else {
            showSetup = true
            finish(error: "Open the Dictate app and finish setup")
            errorMessage = nil
            return
        }
        guard await Recorder.requestMic() else {
            finish(error: "Microphone is off. Turn it on in Settings.")
            return
        }
        errorMessage = nil
        resultText = nil
        phase = .starting
        do {
            // Starting the microphone can take a moment, so keep it off the main thread.
            let recorder = self.recorder
            try await Task.detached { try recorder.start() }.value
        } catch {
            finish(error: "Couldn't start recording, try again")
            return
        }
        startedAt = Date()
        phase = .listening

        if keyboardSession {
            handoff?.clearStopRequest()
            tellKeyboard(.listening)
            stopWatcher = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(300))
                    await self?.checkStopRequest()
                }
            }
        }

        autoStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maxSeconds))
            guard !Task.isCancelled else { return }
            await self?.stopAndSend()
        }
    }

    /// The keyboard asked us to stop (it can't reach the app any other way).
    private func checkStopRequest() async {
        guard keyboardSession, phase == .listening, handoff?.consumeStopRequest() == true else { return }
        await stopAndSend()
    }

    func stopAndSend() async {
        guard phase == .listening else { return }
        autoStop?.cancel()
        autoStop = nil
        stopWatcher?.cancel()
        stopWatcher = nil
        startedAt = nil

        // Keeps the app alive long enough to upload when it is in the background.
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "dictation-upload") {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        defer {
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }

        guard let recording = recorder.stop() else {
            finish(error: "Didn't work, try again")
            return
        }
        defer { try? FileManager.default.removeItem(at: recording.file) }

        guard recording.seconds >= 0.5, let audio = try? Data(contentsOf: recording.file), !audio.isEmpty else {
            finish(error: "Didn't catch that, try again")
            return
        }

        phase = .cleaningUp
        if keyboardSession { tellKeyboard(.cleaningUp) }
        do {
            let result = try await client.dictate(
                audio: audio,
                seconds: Int(recording.seconds.rounded(.up)),
                address: Settings.address,
                token: Settings.token
            )
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                finish(error: "Didn't catch that, try again")
            } else {
                UIPasteboard.general.string = text
                resultText = text
                if keyboardSession { tellKeyboard(.done, text: text) }
                phase = .idle
                keyboardSession = false
            }
        } catch let error as DictationError {
            finish(error: error.message)
        } catch {
            finish(error: DictationError.failed.message)
        }
    }

    /// Ends the current dictation with a plain-language error, here and on the keyboard.
    private func finish(error message: String) {
        errorMessage = message
        if keyboardSession { tellKeyboard(.failed, message: message) }
        phase = .idle
        keyboardSession = false
    }

    private func tellKeyboard(_ phase: HandoffState.Phase, text: String? = nil, message: String? = nil) {
        handoff?.write(HandoffState(phase: phase, text: text, message: message, updatedAt: Date()))
        HandoffSignal.stateChanged.post()
    }
}
