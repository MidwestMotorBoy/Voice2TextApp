import AVFoundation
import Foundation
import Observation
import UIKit

/// The whole app's state: idle → listening → cleaning up → result or error.
/// Never logs audio or transcript text.
///
/// A dictation can be started in the app (button or Action Button), in which case the
/// result goes to the clipboard, or by the keyboard, in which case the result is also
/// handed back to the keyboard to type in.
///
/// The first keyboard dictation opens the app and starts a background "session": the
/// microphone session stays open (audio discarded) so the app stays alive and later
/// keyboard taps can start a dictation without opening the app. The session ends after
/// `SessionInfo.idleLimit` with no dictation, on an interruption such as a phone call,
/// or when the person taps End session.
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
    /// When the background session ends if nothing is dictated; nil when there is no session.
    private(set) var sessionEndsAt: Date?
    var showSetup = false

    private let recorder = Recorder()
    private let client = DictationClient()
    private let handoff = HandoffStore.shared
    private var autoStop: Task<Void, Never>?
    private var sessionLoop: Task<Void, Never>?

    private init() {
        // Anything left over from a previous run of the app is no longer true.
        handoff?.clear()
        handoff?.clearSession()

        for signal in [HandoffSignal.stopRequested, .startRequested] {
            signal.startListening()
            NotificationCenter.default.addObserver(
                forName: signal.localName, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.checkKeyboardRequests() }
            }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in await self?.audioInterrupted() }
        }
    }

    // MARK: Dictation

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
            beginSession()
        } else {
            // A dictation started in the app closes the microphone when it finishes,
            // so any background session is over.
            endSession(closeMicrophone: false)
        }

        autoStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maxSeconds))
            guard !Task.isCancelled else { return }
            await self?.stopAndSend()
        }
    }

    func stopAndSend() async {
        guard phase == .listening else { return }
        autoStop?.cancel()
        autoStop = nil
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

        // While a session is alive the microphone goes back to standby instead of closing.
        guard let recording = recorder.stop(keepSessionActive: sessionEndsAt != nil) else {
            finish(error: "Didn't work, try again")
            return
        }
        extendSession()
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

    // MARK: Background session

    /// Starts the session if there isn't one, and the loop that keeps the keyboard informed.
    private func beginSession() {
        extendSession(startingIfNeeded: true)
        guard sessionLoop == nil else { return }
        sessionLoop = Task { [weak self] in
            var lastHeartbeat = Date.distantPast
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !Task.isCancelled else { return }
                // Not awaited: an upload must not hold up the heartbeat.
                Task { await self.checkKeyboardRequests() }
                if Date().timeIntervalSince(lastHeartbeat) >= SessionInfo.heartbeatInterval {
                    lastHeartbeat = Date()
                    self.sessionTick()
                }
            }
        }
    }

    private func extendSession(startingIfNeeded: Bool = false) {
        guard startingIfNeeded || sessionEndsAt != nil else { return }
        let endsAt = Date().addingTimeInterval(SessionInfo.idleLimit)
        sessionEndsAt = endsAt
        handoff?.writeSession(SessionInfo(heartbeat: Date(), endsAt: endsAt))
    }

    /// Every couple of seconds: refresh the heartbeat, or end the session if it ran out
    /// or the microphone stopped underneath us.
    private func sessionTick() {
        guard let endsAt = sessionEndsAt else { return }
        let busy = phase != .idle
        if !busy, Date() >= endsAt || !recorder.isKeepingAlive {
            endSession()
            return
        }
        handoff?.writeSession(SessionInfo(heartbeat: Date(), endsAt: endsAt))
    }

    /// Ends the background session. Closing the microphone removes the orange indicator.
    func endSession(closeMicrophone: Bool = true) {
        guard sessionEndsAt != nil || sessionLoop != nil else { return }
        sessionLoop?.cancel()
        sessionLoop = nil
        sessionEndsAt = nil
        handoff?.clearSession()
        handoff?.clearStartRequest()
        if closeMicrophone, phase == .idle { recorder.endStandby() }
    }

    /// The keyboard can't call the app directly; it leaves a request and we pick it up.
    private func checkKeyboardRequests() async {
        guard let handoff else { return }
        if phase == .listening, keyboardSession, handoff.consumeStopRequest() {
            await stopAndSend()
        } else if phase == .idle, sessionEndsAt != nil, handoff.consumeStartRequest() {
            await start(fromKeyboard: true)
        }
    }

    /// A phone call or similar took the microphone. Send what we have and end the session:
    /// iOS will not let the app re-open the microphone from the background.
    private func audioInterrupted() async {
        if phase == .listening { await stopAndSend() }
        endSession()
    }
}
