import Foundation
import Observation
import UIKit

/// The whole app's state: idle → listening → cleaning up → result or error.
/// Never logs audio or transcript text.
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
    var showSetup = false

    private let recorder = Recorder()
    private let client = DictationClient()
    private var autoStop: Task<Void, Never>?

    func toggle() async {
        switch phase {
        case .idle: await start()
        case .listening: await stopAndSend()
        case .starting, .cleaningUp: break
        }
    }

    func start() async {
        guard phase == .idle else { return }
        guard Settings.isConfigured else {
            showSetup = true
            return
        }
        guard await Recorder.requestMic() else {
            errorMessage = "Microphone is off. Turn it on in Settings."
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
            errorMessage = "Couldn't start recording, try again"
            phase = .idle
            return
        }
        startedAt = Date()
        phase = .listening

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

        guard let recording = recorder.stop() else {
            phase = .idle
            return
        }
        defer { try? FileManager.default.removeItem(at: recording.file) }

        guard recording.seconds >= 0.5, let audio = try? Data(contentsOf: recording.file), !audio.isEmpty else {
            errorMessage = "Didn't catch that, try again"
            phase = .idle
            return
        }

        phase = .cleaningUp
        do {
            let result = try await client.dictate(
                audio: audio,
                seconds: Int(recording.seconds.rounded(.up)),
                address: Settings.address,
                token: Settings.token
            )
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                errorMessage = "Didn't catch that, try again"
            } else {
                UIPasteboard.general.string = text
                resultText = text
            }
        } catch let error as DictationError {
            errorMessage = error.message
        } catch {
            errorMessage = DictationError.failed.message
        }
        phase = .idle
    }
}
