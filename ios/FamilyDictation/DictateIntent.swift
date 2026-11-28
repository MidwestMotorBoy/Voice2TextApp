import AppIntents

/// "Dictate" for the Action Button, Control Center and Shortcuts:
/// opens the app and starts recording straight away.
struct DictateIntent: AppIntent {
    static var title: LocalizedStringResource = "Dictate"
    static var description = IntentDescription("Open the app and start recording.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await DictationModel.shared.start()
        return .result()
    }
}

struct DictationShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DictateIntent(),
            phrases: [
                "Dictate with \(.applicationName)",
                "Start \(.applicationName)",
            ],
            shortTitle: "Dictate",
            systemImageName: "mic.fill"
        )
    }
}
