import SwiftUI

struct LocalWhisperApp: App {
    @State private var controller = DictationController()
    @AppStorage(Settings.cleanupEnabledKey) private var cleanupEnabled = true
    @State private var launchAtLogin = Settings.launchAtLogin

    var body: some Scene {
        MenuBarExtra {
            Text(status)
            if let p = controller.problem {
                Text(p)
                Button("Open System Settings") { openSettings(for: p) }
            }
            Divider()
            Toggle("Clean up with Apple Intelligence", isOn: $cleanupEnabled)
                .disabled(controller.cleanupUnavailable != nil)
            if let r = controller.cleanupUnavailable { Text(r) }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, v in Settings.launchAtLogin = v; launchAtLogin = Settings.launchAtLogin }
            Divider()
            if !controller.lastTranscript.isEmpty {
                Text("Last: " + controller.lastTranscript.prefix(80))
                Divider()
            }
            Button("Quit LocalWhisper") { _exit(0) } // plain exit() trips a ggml-metal atexit assert in v1.9.2
                .keyboardShortcut("q")
        } label: {
            menuIcon
        }
        .onChange(of: controller.state) { _, _ in controller.refreshPermissions(prompt: false) }
    }

    private var status: String {
        switch controller.state {
        case .idle: "Idle — hold Left Option to dictate"
        case .listening: "Recording…"
        case .transcribing, .cleaning: "Working…"
        case .done: "Inserted"
        case .fallback(let s): s
        }
    }

    @ViewBuilder private var menuIcon: some View {
        switch controller.state {
        case .listening: Image(systemName: "mic.fill").foregroundStyle(.red)
        case .transcribing, .cleaning: Image(systemName: "waveform").symbolEffect(.variableColor)
        default: Image(systemName: "mic")
        }
    }

    private func openSettings(for problem: String) {
        let pane = problem.hasPrefix("Microphone")
            ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        NSWorkspace.shared.open(URL(string: pane)!)
    }
}
