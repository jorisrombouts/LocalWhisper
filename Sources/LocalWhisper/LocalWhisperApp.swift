import AVFoundation
import SwiftUI

struct LocalWhisperApp: App {
    private let controller = DictationController.shared
    @AppStorage(Settings.cleanupEnabledKey) private var cleanupEnabled = true
    @AppStorage(Settings.inputDeviceKey) private var inputDevice = ""

    init() {
        // Start after AppKit has finished launching; Metal init on a background thread before that stalls.
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DictationController.shared.start() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Text(status)
            if let p = controller.problem {
                Text(p)
                Button("Open System Settings…") { openSettings(for: p) }
            }
            Divider()
            Toggle("Clean Up with Apple Intelligence", isOn: $cleanupEnabled)
                .disabled(controller.cleanupUnavailable != nil)
            if let r = controller.cleanupUnavailable { Text(r) }
            Toggle("Launch at Login", isOn: Binding(get: { Settings.launchAtLogin }, set: { Settings.launchAtLogin = $0 }))
            Picker("Microphone", selection: $inputDevice) {
                Text("System Default").tag("")
                ForEach(AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices, id: \.uniqueID) {
                    Text($0.localizedName).tag($0.uniqueID)
                }
            }
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
        case .listening: Image(systemName: "waveform.badge.mic")
        case .transcribing, .cleaning: Image(systemName: "waveform").symbolEffect(.variableColor)
        default: Image(systemName: "waveform")
        }
    }

    private func openSettings(for problem: String) {
        let pane = problem.hasPrefix("Microphone")
            ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        NSWorkspace.shared.open(URL(string: pane)!)
    }
}
