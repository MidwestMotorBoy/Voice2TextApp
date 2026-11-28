import UIKit

/// The Dictate keyboard: one big mic button plus globe, space, backspace and return.
///
/// iOS keyboards cannot use the microphone, so tapping the mic opens the main app,
/// which records in the background. After that first time the app stays ready for a
/// while, and the mic just signals it. Tapping stop asks the app to send the audio;
/// the cleaned-up text comes back through the shared App Group and is typed in here.
/// Nothing is logged, and the shared result is cleared as soon as it is inserted.
final class KeyboardViewController: UIInputViewController {
    private enum Display: Equatable {
        case needsFullAccess
        case idle(message: String?)
        case opening
        case listening
        case cleaningUp
    }

    private let statusLabel = UILabel()
    private let micButton = UIButton(type: .custom)
    private let spinner = UIActivityIndicatorView(style: .large)
    private let globeButton = UIButton(type: .system)

    private var display: Display = .idle(message: nil)
    private var pollTimer: Timer?
    private var openDeadline: Date?
    /// Set while waiting for a live background session to start listening.
    private var startDeadline: Date?
    private var stopRequestedAt: Date?
    private var lastMessage: String?
    private var signalObserver: NSObjectProtocol?

    private static let appURL = URL(string: "familydictation://record")!

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        HandoffSignal.stateChanged.startListening()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        signalObserver = NotificationCenter.default.addObserver(
            forName: HandoffSignal.stateChanged.localName, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pollTimer?.invalidate()
        pollTimer = nil
        if let signalObserver { NotificationCenter.default.removeObserver(signalObserver) }
        signalObserver = nil
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        globeButton.isHidden = !needsInputModeSwitchKey
    }

    // MARK: State

    private func refresh() {
        guard hasFullAccess, let store = HandoffStore.shared else {
            show(.needsFullAccess)
            return
        }
        let now = Date()
        let state = store.read().effective(now: now)

        switch state.phase {
        case .done:
            if let text = state.text, !text.isEmpty {
                textDocumentProxy.insertText(text + " ")
            }
            store.clear()
            resetPending()
            lastMessage = nil
            show(.idle(message: nil))

        case .failed:
            store.clear()
            resetPending()
            lastMessage = state.message ?? "Didn't work, try again"
            show(.idle(message: lastMessage))

        case .cleaningUp:
            openDeadline = nil
            startDeadline = nil
            show(.cleaningUp)

        case .listening:
            openDeadline = nil
            startDeadline = nil
            if let requested = stopRequestedAt {
                if now.timeIntervalSince(requested) > 10 {
                    // The app never answered the stop request (it was probably closed).
                    store.clear()
                    resetPending()
                    lastMessage = "Didn't work, try again"
                    show(.idle(message: lastMessage))
                } else {
                    show(.cleaningUp)
                }
            } else {
                show(.listening)
            }

        case .idle:
            stopRequestedAt = nil
            if let deadline = startDeadline {
                if now > deadline {
                    // The session didn't answer (the app was closed or suspended): open the app instead.
                    startDeadline = nil
                    store.clearStartRequest()
                    openDeadline = now.addingTimeInterval(5)
                    openApp()
                }
                show(.opening)
            } else if let deadline = openDeadline {
                if now > deadline {
                    openDeadline = nil
                    lastMessage = "Couldn't start. Open the Dictate app once, then try again."
                    show(.idle(message: lastMessage))
                } else {
                    show(.opening)
                }
            } else {
                show(.idle(message: lastMessage))
            }
        }
    }

    private func resetPending() {
        openDeadline = nil
        startDeadline = nil
        stopRequestedAt = nil
    }

    private func show(_ newDisplay: Display) {
        guard newDisplay != display || statusLabel.text == nil else { return }
        display = newDisplay

        var color = UIColor.systemBlue
        var icon = "mic.fill"
        var busy = false
        var enabled = true
        statusLabel.textColor = .label

        switch newDisplay {
        case .needsFullAccess:
            statusLabel.text = "Turn on Allow Full Access in Settings"
            statusLabel.textColor = .systemRed
            color = .systemGray
            enabled = false
        case .idle(let message):
            statusLabel.text = message ?? "Tap to dictate"
            if message != nil { statusLabel.textColor = .systemRed }
        case .opening:
            statusLabel.text = "Starting…"
            color = .systemGray
            busy = true
            enabled = false
        case .listening:
            statusLabel.text = "Listening… tap to stop"
            color = .systemRed
            icon = "stop.fill"
        case .cleaningUp:
            statusLabel.text = "Cleaning up…"
            color = .systemGray
            busy = true
            enabled = false
        }

        micButton.backgroundColor = color
        micButton.isEnabled = enabled
        let symbol = UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)
        micButton.setImage(busy ? nil : UIImage(systemName: icon, withConfiguration: symbol), for: .normal)
        if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    // MARK: Actions

    @objc private func micTapped() {
        guard hasFullAccess, let store = HandoffStore.shared else { return }
        switch display {
        case .idle:
            lastMessage = nil
            store.clear()
            if store.session()?.isAlive() == true {
                // The app is ready in the background: ask it to start, no app switch needed.
                startDeadline = Date().addingTimeInterval(SessionInfo.startAckTimeout)
                store.requestStart()
                HandoffSignal.startRequested.post()
            } else {
                openDeadline = Date().addingTimeInterval(5)
                openApp()
            }
            refresh()
        case .listening:
            stopRequestedAt = Date()
            store.requestStop()
            HandoffSignal.stopRequested.post()
            refresh()
        case .needsFullAccess, .opening, .cleaningUp:
            break
        }
    }

    /// Opens the main app. Keyboards have no public way to open a URL, so this walks
    /// up to the application object and calls its `openURL:options:completionHandler:`.
    /// Check this still works after each major iOS update.
    private func openApp() {
        let selector = sel_registerName("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector) {
                typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let implementation = current.method(for: selector)
                unsafeBitCast(implementation, to: OpenURL.self)(
                    current, selector, Self.appURL as NSURL, NSDictionary(), nil)
                return
            }
            responder = current.next
        }
    }

    @objc private func spaceTapped() { textDocumentProxy.insertText(" ") }
    @objc private func returnTapped() { textDocumentProxy.insertText("\n") }
    @objc private func backspaceTapped() { textDocumentProxy.deleteBackward() }

    // MARK: Layout

    private func buildLayout() {
        let height = view.heightAnchor.constraint(equalToConstant: 250)
        height.priority = .init(999)
        height.isActive = true

        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.7

        micButton.tintColor = .white
        micButton.layer.cornerRadius = 46
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        micButton.accessibilityLabel = "Dictate"
        micButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            micButton.widthAnchor.constraint(equalToConstant: 92),
            micButton.heightAnchor.constraint(equalToConstant: 92),
        ])

        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.isUserInteractionEnabled = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        micButton.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: micButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: micButton.centerYAnchor),
        ])

        configureKey(globeButton, symbol: "globe", label: "Next keyboard")
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let space = UIButton(type: .system)
        configureKey(space, title: "space", label: "Space")
        space.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)

        let backspace = UIButton(type: .system)
        configureKey(backspace, symbol: "delete.left", label: "Delete")
        backspace.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)

        let enter = UIButton(type: .system)
        configureKey(enter, symbol: "return", label: "Return")
        enter.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)

        let keys = UIStackView(arrangedSubviews: [globeButton, space, backspace, enter])
        keys.axis = .horizontal
        keys.spacing = 6
        for key in [globeButton, backspace, enter] {
            key.widthAnchor.constraint(equalToConstant: 52).isActive = true
        }
        keys.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let micRow = UIStackView(arrangedSubviews: [micButton])
        micRow.axis = .vertical
        micRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [statusLabel, micRow, keys])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])
    }

    private func configureKey(_ button: UIButton, symbol: String? = nil, title: String? = nil, label: String) {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .secondarySystemBackground
        config.baseForegroundColor = .label
        config.cornerStyle = .medium
        if let symbol { config.image = UIImage(systemName: symbol) }
        if let title { config.title = title }
        button.configuration = config
        button.accessibilityLabel = label
    }
}
