import SwiftUI

/// First-launch setup: Worker address, family token and microphone permission.
struct SetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var address = Settings.address
    @State private var token = Settings.token
    @State private var micAllowed = Recorder.micAllowed

    private var canSave: Bool {
        DictationClient.endpoint(from: address) != nil
            && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("your-worker.workers.dev", text: $address)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Worker address")
                } footer: {
                    Text("The web address you were given for the family dictation service.")
                }

                Section {
                    SecureField("Paste your token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Family token")
                } footer: {
                    Text("Your personal token. It is stored securely on this phone.")
                }

                Section("Microphone") {
                    if micAllowed {
                        Label("Microphone allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow microphone") {
                            Task { micAllowed = await Recorder.requestMic() }
                        }
                    }
                }
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Settings.address = address
                        Settings.token = token
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
