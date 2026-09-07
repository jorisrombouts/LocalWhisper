import Foundation
import AVFoundation

// Step 1 harness: `LocalWhisper --transcribe file.wav`
let args = CommandLine.arguments
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
    exit(0)
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
