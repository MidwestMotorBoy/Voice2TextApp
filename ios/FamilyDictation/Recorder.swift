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

    func start() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default)
        try audioSession.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let newRecorder = try AVAudioRecorder(url: url, settings: settings)
        guard newRecorder.record() else {
            try? FileManager.default.removeItem(at: url)
            throw CocoaError(.fileWriteUnknown)
        }
        recorder = newRecorder
    }

    /// Stops recording. Returns the file and its length in seconds, or nil if nothing was recording.
    func stop() -> (file: URL, seconds: Double)? {
        guard let current = recorder else { return nil }
        let seconds = current.currentTime
        current.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return (current.url, seconds)
    }
}
