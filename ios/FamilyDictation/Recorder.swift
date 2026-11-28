import AVFoundation

/// Records the microphone to a temporary .m4a (AAC, 16 kHz, mono, ~32 kbps).
/// Only ever used by DictationModel, one call at a time.
final class Recorder: @unchecked Sendable {
    private var recorder: AVAudioRecorder?

    static var micAllowed: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    static func requestMic() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    private var standby: AVAudioRecorder?

    private static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
    ]

    private func activateSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default)
        try audioSession.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func start() throws {
        try activateSession()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-\(UUID().uuidString).m4a")
        let newRecorder = try AVAudioRecorder(url: url, settings: Self.settings)
        guard newRecorder.record() else {
            try? FileManager.default.removeItem(at: url)
            throw CocoaError(.fileWriteUnknown)
        }
        recorder = newRecorder
        // The real recording is running, so the standby one is no longer needed.
        standby?.stop()
        standby = nil
    }

    /// Stops recording. Returns the file and its length in seconds, or nil if nothing was recording.
    /// With `keepSessionActive`, the microphone session stays open for a background session:
    /// iOS does not let an app re-open it from the background.
    func stop(keepSessionActive: Bool = false) -> (file: URL, seconds: Double)? {
        guard let current = recorder else { return nil }
        if keepSessionActive { try? startStandby() }
        let seconds = current.currentTime
        current.stop()
        recorder = nil
        if !keepSessionActive { deactivateSession() }
        return (current.url, seconds)
    }

    // MARK: Standby (background session)

    /// Keeps the microphone session open so the app stays alive in the background and can
    /// start a dictation without being opened. The audio goes to /dev/null: nothing is
    /// written to disk or sent anywhere while on standby.
    func startStandby() throws {
        guard standby?.isRecording != true else { return }
        try activateSession()
        let discard = try AVAudioRecorder(url: URL(fileURLWithPath: "/dev/null"), settings: Self.settings)
        guard discard.record() else { throw CocoaError(.fileWriteUnknown) }
        standby = discard
    }

    /// True while either the standby or a real recording is running.
    var isKeepingAlive: Bool {
        standby?.isRecording == true || recorder?.isRecording == true
    }

    /// Ends standby and closes the microphone session (the orange indicator goes away).
    func endStandby() {
        standby?.stop()
        standby = nil
        if recorder == nil { deactivateSession() }
    }
}
