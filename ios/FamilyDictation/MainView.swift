import SwiftUI

struct MainView: View {
    @Bindable var model: DictationModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 0)

                Button {
                    Task { await model.toggle() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(buttonColor)
                            .frame(width: 220, height: 220)
                            .shadow(radius: 8, y: 4)
                        if model.phase == .cleaningUp || model.phase == .starting {
                            ProgressView()
                                .controlSize(.extraLarge)
                                .tint(.white)
                        } else {
                            Image(systemName: model.phase == .listening ? "stop.fill" : "mic.fill")
                                .font(.system(size: 84, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.phase == .cleaningUp || model.phase == .starting)
                .accessibilityLabel(model.phase == .listening ? "Stop" : "Start dictating")

                status
                    .font(.title2.weight(.medium))
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 60)

                if let text = model.resultText {
                    resultCard(text)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Dictate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.showSetup = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Setup")
                    .disabled(model.phase != .idle)
                }
            }
            .sheet(isPresented: $model.showSetup) {
                SetupView()
            }
            .onAppear {
                if !Settings.isConfigured { model.showSetup = true }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Recording can't continue in the background, so send what we have.
                if newPhase == .background, model.phase == .listening {
                    Task { await model.stopAndSend() }
                }
            }
        }
    }

    private var buttonColor: Color {
        switch model.phase {
        case .idle: return .blue
        case .listening: return .red
        case .starting, .cleaningUp: return .gray
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .listening:
            VStack(spacing: 4) {
                Text("Listening…")
                if let startedAt = model.startedAt {
                    Text(startedAt, style: .timer)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("Tap to stop")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .starting:
            Text("Starting…")
        case .cleaningUp:
            Text("Cleaning up…")
        case .idle:
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            } else if model.resultText == nil {
                Text("Tap and talk").foregroundStyle(.secondary)
            } else {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func resultCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)

            ShareLink(item: text) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
