import AppKit
import AVFoundation

let args = CommandLine.arguments

// Cleanup check: `LocalWhisper --clean "raw text"`
if let i = args.firstIndex(of: "--clean"), i + 1 < args.count {
    if let r = Cleaner.unavailableReason { print(r); exit(1) }
    let cleaner = Cleaner()
    Task { @MainActor in
        await cleaner.warmUp()
        let t0 = Date()
        let out = await cleaner.clean(args[i + 1])
        print("clean_ms", Int(Date().timeIntervalSince(t0) * 1000), "cleaned", out != nil)
        print("text:", out ?? "(fallback)")
        exit(0)
    }
    RunLoop.main.run()
}

// Engine check: `LocalWhisper --transcribe file.wav`
if let i = args.firstIndex(of: "--transcribe"), i + 1 < args.count {
    let t0 = Date()
    let engine = try WhisperEngine(modelPath: DictationController.modelURL()!.path)
    print("load_ms", Int(Date().timeIntervalSince(t0) * 1000))

    let samples = try loadSamples16k(URL(fileURLWithPath: args[i + 1]))
    print("audio_s", Double(samples.count) / 16_000)

    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        await engine.warmUp()
        let t1 = Date()
        let text = await engine.transcribe(samples)
        print("whisper_ms", Int(Date().timeIntervalSince(t1) * 1000))
        print("text:", text)
        sem.signal()
    }
    sem.wait()
    fflush(stdout); _exit(0) // ggml-metal v1.9.2 asserts in its atexit teardown
}

func loadSamples16k(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: inBuf)
    let conv = AVAudioConverter(from: file.processingFormat, to: target)!
    let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 1)!
    var fed = false
    var err: NSError?
    conv.convert(to: outBuf, error: &err) { _, status in
        if fed { status.pointee = .endOfStream; return nil }
        fed = true; status.pointee = .haveData; return inBuf
    }
    if let err { throw err }
    return Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: Int(outBuf.frameLength)))
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
if let i = args.firstIndex(of: "--launch-at-login"), i + 1 < args.count {
    Settings.launchAtLogin = args[i + 1] == "on"
    print("launch at login:", Settings.launchAtLogin ? "on" : "off", "(\(Bundle.main.bundlePath))")
    exit(0)
}

// Normal launch: the menu bar app. stderr (whisper + NSLog) goes to ~/Library/Logs/LocalWhisper.log.
let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/LocalWhisper.log").path
freopen(logPath, "a", stderr)
NSApplication.shared.setActivationPolicy(.accessory)
LocalWhisperApp.main()
