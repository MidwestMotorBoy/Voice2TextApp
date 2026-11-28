import Foundation

/// The App Group shared by the app and its keyboard. The id comes from the
/// `AppGroupID` Info.plist value (set from a build setting), never from code.
enum AppGroup {
    static var id: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
              !value.isEmpty else { return nil }
        return value
    }

    static var containerURL: URL? {
        id.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }
}

/// What the app tells the keyboard about a dictation the keyboard started.
struct HandoffState: Codable, Equatable {
    enum Phase: String, Codable { case idle, listening, cleaningUp, done, failed }

    var phase: Phase
    var text: String?
    var message: String?
    var updatedAt: Date

    static let idle = HandoffState(phase: .idle, text: nil, message: nil, updatedAt: .distantPast)

    /// Longest the app records before stopping by itself, plus a margin.
    static let maxListening: TimeInterval = 5 * 60 + 60
    /// Longest the keyboard waits for the cleaned-up text before giving up.
    static let maxCleaning: TimeInterval = 90
    /// A result older than this is dropped rather than typed into some unrelated text box.
    static let maxResultAge: TimeInterval = 120

    /// The state as the keyboard should treat it right now, so it never waits forever
    /// on an app that was closed or a request that hung.
    func effective(now: Date = Date()) -> HandoffState {
        let age = now.timeIntervalSince(updatedAt)
        switch phase {
        case .idle:
            return self
        case .listening:
            return age > Self.maxListening ? .idle : self
        case .cleaningUp:
            return age > Self.maxCleaning
                ? HandoffState(phase: .failed, text: nil, message: "Didn't work, try again", updatedAt: now)
                : self
        case .done, .failed:
            return age > Self.maxResultAge ? .idle : self
        }
    }
}

/// The app's background "session": while it is alive the keyboard can start a dictation
/// without opening the app. The app refreshes `heartbeat` every couple of seconds.
struct SessionInfo: Codable, Equatable {
    var heartbeat: Date
    var endsAt: Date

    /// How long a session lasts with no dictation.
    static let idleLimit: TimeInterval = 10 * 60
    /// How often the app refreshes the heartbeat.
    static let heartbeatInterval: TimeInterval = 2
    /// A heartbeat older than this means the app is gone (closed, suspended or interrupted).
    static let heartbeatTimeout: TimeInterval = 6
    /// How long the keyboard waits for a live session to start listening before opening the app instead.
    static let startAckTimeout: TimeInterval = 1.5

    func isAlive(now: Date = Date()) -> Bool {
        now < endsAt && now.timeIntervalSince(heartbeat) < Self.heartbeatTimeout
    }
}

/// A few small files in the shared container: the app's state, its session heartbeat,
/// and the keyboard's "start" and "stop" requests.
/// The transcript is only here between the app finishing and the keyboard typing it in.
struct HandoffStore {
    let directory: URL

    static var shared: HandoffStore? {
        AppGroup.containerURL.map { HandoffStore(directory: $0) }
    }

    private var stateURL: URL { directory.appendingPathComponent("handoff-state.json") }
    private var stopURL: URL { directory.appendingPathComponent("handoff-stop") }

    private var startURL: URL { directory.appendingPathComponent("handoff-start") }
    private var sessionURL: URL { directory.appendingPathComponent("handoff-session.json") }

    func read() -> HandoffState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(HandoffState.self, from: data) else { return .idle }
        return state
    }

    func write(_ state: HandoffState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    /// Clears the result and any pending requests. The session heartbeat is left alone.
    func clear() {
        try? FileManager.default.removeItem(at: stateURL)
        try? FileManager.default.removeItem(at: stopURL)
        try? FileManager.default.removeItem(at: startURL)
    }

    // MARK: Session heartbeat (written by the app, read by the keyboard)

    func session() -> SessionInfo? {
        guard let data = try? Data(contentsOf: sessionURL) else { return nil }
        return try? JSONDecoder().decode(SessionInfo.self, from: data)
    }

    func writeSession(_ info: SessionInfo) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        try? data.write(to: sessionURL, options: .atomic)
    }

    func clearSession() {
        try? FileManager.default.removeItem(at: sessionURL)
    }

    /// Keyboard → app: start a dictation in the background (only useful while a session is alive).
    func requestStart() {
        try? Data().write(to: startURL, options: .atomic)
    }

    /// App: true once per start request.
    func consumeStartRequest() -> Bool {
        guard FileManager.default.fileExists(atPath: startURL.path) else { return false }
        try? FileManager.default.removeItem(at: startURL)
        return true
    }

    func clearStartRequest() {
        try? FileManager.default.removeItem(at: startURL)
    }

    /// Keyboard → app: please stop recording and send.
    func requestStop() {
        try? Data().write(to: stopURL, options: .atomic)
    }

    /// App: true once per stop request.
    func consumeStopRequest() -> Bool {
        guard FileManager.default.fileExists(atPath: stopURL.path) else { return false }
        try? FileManager.default.removeItem(at: stopURL)
        return true
    }

    func clearStopRequest() {
        try? FileManager.default.removeItem(at: stopURL)
    }
}

/// Cross-process nudges so the other side re-reads the shared files straight away.
/// Both sides also poll, so a missed nudge only costs a fraction of a second.
enum HandoffSignal: String {
    case stateChanged = "state-changed"
    case stopRequested = "stop-requested"
    case startRequested = "start-requested"

    private var darwinName: CFString? {
        AppGroup.id.map { "\($0).\(rawValue)" as CFString }
    }

    /// Posted locally (on the main queue) when the other process sends this signal.
    var localName: Notification.Name { Notification.Name("HandoffSignal.\(rawValue)") }

    func post() {
        guard let name = darwinName else { return }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name), nil, nil, true)
    }

    /// Call once per process for each signal it wants to hear.
    func startListening() {
        guard let name = darwinName else { return }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, name, _, _ in
                guard let raw = name?.rawValue as String?,
                      let suffix = raw.split(separator: ".").last,
                      let signal = HandoffSignal(rawValue: String(suffix)) else { return }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: signal.localName, object: nil)
                }
            },
            name, nil, .deliverImmediately)
    }
}
