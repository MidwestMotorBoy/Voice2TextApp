import SwiftUI

@main
struct FamilyDictationApp: App {
    var body: some Scene {
        WindowGroup {
            MainView(model: DictationModel.shared)
        }
    }
}
