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
    private(set) var level: Float = 0      // 0...1 for the meter, see onLevel below
    private var noiseFloor: Float = 0.01
    private var peakHold: Float = 0.01
    private(set) var lastTranscript = ""
    private(set) var problem: String?          // shown in the menu
    private var engineProblem: String?
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
        if let dir = arg(after: "--overlay-demo") { demoOverlay(to: dir) }
        recorder.onLevel = { [self] l in Task { @MainActor in
            // Meter like the system ones: nothing below the noise floor, full at the recent peak, fast rise and slow fall.
            if l < peakHold * 0.25 { noiseFloor += (l - noiseFloor) * 0.05 }   // average of the quiet stretches
            peakHold = max(l, peakHold * 0.98, noiseFloor * 5)                  // recent peak, never within 5x of the floor
            let rel = max(0, l - noiseFloor * 3) / max(peakHold - noiseFloor * 3, 1e-4)   // noise varies ~2x; 3x is the dead zone
            level = max(rel, level * 0.8)
        } }
        hotkey.onPress = { [self] in press() }
        hotkey.onRelease = { [self] in release() }
        hotkey.onCancel = { [self] in cancel() }
        hotkey.start()
        refreshPermissions(prompt: true)

        guard let url = Self.modelURL() else { engineProblem = "Model file ggml-large-v3-turbo.bin not found"; refreshPermissions(prompt: false); return }
        Task.detached { [self] in
            let t0 = Date()
            do {
                let e = try WhisperEngine(modelPath: url.path)
                await e.warmUp()
                await MainActor.run { engine = e }
                NSLog("engine ready in %d ms", Int(Date().timeIntervalSince(t0) * 1000))
            } catch {
                NSLog("engine failed: %@", error.localizedDescription)
                await MainActor.run { engineProblem = error.localizedDescription; refreshPermissions(prompt: false) }
            }
        }
        if cleanupUnavailable == nil { Task { await cleaner.warmUp() } }
    }

    func refreshPermissions(prompt: Bool) {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        if mic == .notDetermined { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
        problem = !HotkeyMonitor.ensureAccessibility(prompt: prompt) ? "Accessibility permission missing (needed to paste)"
            : mic == .denied ? "Microphone access denied" : engineProblem
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
            let audioSeconds = Double(samples.count) / AudioRecorder.sampleRate
            var text = await engine.transcribe(samples)
            let whisperMs = ms(since: t0)
            guard !text.isEmpty else { finish(); return }

            var cleanMs = 0
            var fellBack = false
            if Settings.cleanupEnabled, cleanupUnavailable == nil, text.split(separator: " ").count >= 4 {
                state = .cleaning
                let t1 = Date()
                if let cleaned = await cleaner.clean(text, audioSeconds: audioSeconds) { text = cleaned } else { fellBack = true }
                cleanMs = ms(since: t1)
            }

            let t2 = Date()
            TextInserter.insert(text)
            lastTranscript = text
            NSLog("dictation audio_s=%.1f whisper_ms=%d clean_ms=%d insert_ms=%d fallback=%d",
                  audioSeconds, whisperMs, cleanMs, ms(since: t2), fellBack ? 1 : 0)
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
        level = 0.7
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
