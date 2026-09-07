import Foundation
import AVFoundation

import AppKit

let args = CommandLine.arguments

// Step 6 harness: `LocalWhisper --clean "raw text"`
if let i = args.firstIndex(of: "--clean"), i + 1 < args.count {
    if let r = Cleaner.unavailableReason { print(r); exit(1) }
    let cleaner = Cleaner()
    Task { @MainActor in
        await cleaner.warmUp()
        let t0 = Date()
        let (out, ok) = await cleaner.clean(args[i + 1])
        print("clean_ms", Int(Date().timeIntervalSince(t0) * 1000), "cleaned", ok)
        print("text:", out)
        exit(0)
    }
    RunLoop.main.run()
}

// Step 1 harness: `LocalWhisper --transcribe file.wav`
if let i = args.firstIndex(of: "--transcribe"), i + 1 < args.count {
    let modelPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/ggml-large-v3-turbo.bin").path
    let t0 = Date()
    let engine = try WhisperEngine(modelPath: modelPath)
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

// Step 2 harness: `LocalWhisper --record 3`
if let i = args.firstIndex(of: "--record"), i + 1 < args.count, let secs = Double(args[i + 1]) {
    let modelPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/ggml-large-v3-turbo.bin").path
    let engine = try WhisperEngine(modelPath: modelPath)
    let recorder = AudioRecorder()
    recorder.onLevel = { level in if level > 0.02 { FileHandle.standardError.write("level \(level)\n".data(using: .utf8)!) } }
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        await engine.warmUp()
        print("recording \(secs)s... speak now"); fflush(stdout)
        try recorder.start()
        try await Task.sleep(for: .seconds(secs))
        guard let samples = recorder.stop() else { print("clip too short"); sem.signal(); return }
        print("audio_s", Double(samples.count) / 16_000)
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

// Normal launch: the menu bar app. stderr (whisper + NSLog) goes to ~/Library/Logs/LocalWhisper.log.
let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/LocalWhisper.log").path
freopen(logPath, "a", stderr)
NSApplication.shared.setActivationPolicy(.accessory)
let app = LocalWhisperApp()
_ = app
LocalWhisperApp.main()
