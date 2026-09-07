import AppKit
import AVFoundation

let args = CommandLine.arguments
func arg(after flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }

// Cleanup check: `LocalWhisper --clean "raw text"`
if let raw = arg(after: "--clean") {
    if let r = Cleaner.unavailableReason { print(r); exit(1) }
    let cleaner = Cleaner()
    Task { @MainActor in
        await cleaner.warmUp()
        let t0 = Date()
        let out = await cleaner.clean(raw, audioSeconds: Double(raw.count) / 15)   // ~15 chars per second of speech
        print("clean_ms", Int(Date().timeIntervalSince(t0) * 1000), "cleaned", out != nil)
        print("text:", out ?? "(fallback)")
        exit(0)
    }
    RunLoop.main.run()
}

// Engine check: `LocalWhisper --transcribe file.wav`
if let path = arg(after: "--transcribe") {
    let t0 = Date()
    let engine = try WhisperEngine(modelPath: DictationController.modelURL()!.path)
    print("load_ms", Int(Date().timeIntervalSince(t0) * 1000))
    let samples = try loadSamples16k(URL(fileURLWithPath: path))
    print("audio_s", Double(samples.count) / 16_000)
    Task {
        await engine.warmUp()
        let t1 = Date()
        let text = await engine.transcribe(samples)
        print("whisper_ms", Int(Date().timeIntervalSince(t1) * 1000))
        print("text:", text)
        fflush(stdout); _exit(0) // ggml-metal v1.9.2 asserts in its atexit teardown
    }
    RunLoop.main.run()
}

func loadSamples16k(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buf)
    return AudioRecorder.resample(buf, with: AVAudioConverter(from: file.processingFormat, to: AudioRecorder.format)!)
}

// Insert self-test: `LocalWhisper --insert-test` pastes a fixed string into the frontmost app after 3 s.
if args.contains("--insert-test") {
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(3))
        TextInserter.insert("hello from LocalWhisper")
        try? await Task.sleep(for: .seconds(1))
        exit(0)
    }
    RunLoop.main.run()
}

// `LocalWhisper --launch-at-login on|off` (run from the installed bundle) registers the app with launchd.
if let mode = arg(after: "--launch-at-login") {
    Settings.launchAtLogin = mode == "on"
    print("launch at login:", Settings.launchAtLogin ? "on" : "off", "(\(Bundle.main.bundlePath))")
    exit(0)
}

// Normal launch: the menu bar app. stderr (whisper + NSLog) goes to ~/Library/Logs/LocalWhisper.log.
let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/LocalWhisper.log").path
freopen(logPath, "a", stderr)
NSApplication.shared.setActivationPolicy(.accessory)
LocalWhisperApp.main()
