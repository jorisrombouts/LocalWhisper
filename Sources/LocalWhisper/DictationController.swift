import AppKit
import AVFoundation
import Observation
import SwiftUI

/// idle → listening → transcribing → cleaning → done. Owns every component; the UI is a function of `state`.
@MainActor
@Observable
final class DictationController {
    static let shared = DictationController()
    enum State: Equatable {
        case idle, listening, transcribing, cleaning, done
        case fallback(String)
    }

    private(set) var state: State = .idle
    private(set) var level: Float = 0
    private(set) var lastTranscript = ""
    private(set) var problem: String?          // shown in the menu
    private(set) var cleanupUnavailable: String? = Cleaner.unavailableReason

    private let recorder = AudioRecorder()
    private let hotkey = HotkeyMonitor()
    private let cleaner = Cleaner()
    private var engine: WhisperEngine?
    private var started = false
    @ObservationIgnored private lazy var overlay = RecordingOverlay(controller: self)

    static func modelURL() -> URL? {
        if let u = Bundle.main.url(forResource: "ggml-large-v3-turbo", withExtension: "bin") { return u }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/ggml-large-v3-turbo.bin")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    func start() {
        guard !started else { return }
        started = true
        recorder.onLevel = { [self] l in Task { @MainActor in level = l } }
        hotkey.onPress = { [self] in press() }
        hotkey.onRelease = { [self] in release() }
        hotkey.onCancel = { [self] in cancel() }
        hotkey.start()
        refreshPermissions(prompt: true)

        guard let url = Self.modelURL() else { problem = "Model file ggml-large-v3-turbo.bin not found"; return }
        Task.detached { [self] in
            let t0 = Date()
            do {
                let e = try WhisperEngine(modelPath: url.path)
                await e.warmUp()
                await MainActor.run { engine = e }
                NSLog("engine ready in %d ms", Int(Date().timeIntervalSince(t0) * 1000))
            } catch {
                NSLog("engine failed: %@", error.localizedDescription)
                await MainActor.run { problem = error.localizedDescription }
            }
        }
        if cleanupUnavailable == nil { Task { await cleaner.warmUp() } }
    }

    func refreshPermissions(prompt: Bool) {
        if !HotkeyMonitor.ensureAccessibility(prompt: prompt) {
            problem = "Accessibility permission missing (needed for the hotkey and paste)"
        } else if AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
            problem = "Microphone access denied"
        } else if problem?.hasPrefix("Accessibility") == true || problem?.hasPrefix("Microphone") == true {
            problem = nil
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
    }

    private func press() {
        guard state == .idle || state == .done else { return }
        guard engine != nil else { show(.fallback("Model still loading")); return }
        do {
            try recorder.start()
            state = .listening
            overlay.show()
        } catch {
            show(.fallback(error.localizedDescription))
        }
    }

    private func cancel() {
        guard state == .listening else { return }
        _ = recorder.stop()
        finish()
    }

    private func release() {
        guard state == .listening, let engine else { return }
        guard let samples = recorder.stop() else { finish(); return }
        state = .transcribing
        Task {
            let t0 = Date()
            var text = await engine.transcribe(samples)
            let whisperMs = ms(since: t0)
            guard !text.isEmpty else { finish(); return }

            var cleanMs = 0
            var fellBack = false
            if Settings.cleanupEnabled, cleanupUnavailable == nil, text.split(separator: " ").count >= 4 {
                state = .cleaning
                let t1 = Date()
                if let cleaned = await cleaner.clean(text) { text = cleaned } else { fellBack = true }
                cleanMs = ms(since: t1)
            }

            let t2 = Date()
            TextInserter.insert(text)
            lastTranscript = text
            NSLog("dictation audio_s=%.1f whisper_ms=%d clean_ms=%d insert_ms=%d fallback=%d",
                  Double(samples.count) / AudioRecorder.sampleRate, whisperMs, cleanMs, ms(since: t2), fellBack ? 1 : 0)
            state = fellBack ? .fallback("Raw text inserted") : .done
            try? await Task.sleep(for: .milliseconds(fellBack ? 1500 : 700))
            finish()
        }
    }

    private func show(_ s: State) {
        state = s
        overlay.show()
        Task { try? await Task.sleep(for: .seconds(1.2)); finish() }
    }

    private func finish() {
        state = .idle
        level = 0
        overlay.hide()
    }

    /// `--overlay-demo <dir>`: render every overlay state to <dir>/overlay-<state>.png and exit.
    func demoOverlay(to dir: String) {
        let states: [(String, State)] = [("listening", .listening), ("transcribing", .transcribing), ("cleaning", .cleaning),
                                         ("done", .done), ("fallback", .fallback("Raw text inserted"))]
        level = 0.08
        for (name, s) in states {
            state = s
            let r = ImageRenderer(content: OverlayView(controller: self).background(.blue.opacity(0.3)))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("overlay-\(name).png"))
            }
        }
        _exit(0)
    }

    private func ms(since d: Date) -> Int { Int(Date().timeIntervalSince(d) * 1000) }
}
