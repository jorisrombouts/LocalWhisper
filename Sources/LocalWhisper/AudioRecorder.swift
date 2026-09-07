import AVFoundation

/// AVAudioEngine tap -> 16 kHz mono Float samples. RMS level per buffer via `onLevel` (audio thread).
final class AudioRecorder: @unchecked Sendable {
    static let sampleRate = 16_000.0
    static let minSeconds = 0.4

    var onLevel: (@Sendable (Float) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    func start() throws {
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        let input = engine.inputNode
        let native = input.outputFormat(forBus: 0)
        guard native.sampleRate > 0 else { throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No input device"]) }
        converter = AVAudioConverter(from: native, to: Self.format)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: native) { [weak self] buf, _ in
            self?.consume(buf)
        }
        engine.prepare()
        try engine.start()
    }

    /// Returns the samples, or nil when the clip is too short to be worth transcribing.
    func stop() -> [Float]? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let out = lock.withLock { samples }
        return Double(out.count) / Self.sampleRate < Self.minSeconds ? nil : out
    }

    private func consume(_ buf: AVAudioPCMBuffer) {
        guard let converter else { return }
        let chunk = Self.resample(buf, with: converter)
        guard !chunk.isEmpty else { return }
        lock.withLock { samples.append(contentsOf: chunk) }
        onLevel?((chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count)).squareRoot())
    }

    /// One buffer through the converter to 16 kHz mono Float samples.
    static func resample(_ buf: AVAudioPCMBuffer, with converter: AVAudioConverter) -> [Float] {
        let ratio = converter.outputFormat.sampleRate / buf.format.sampleRate
        let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: AVAudioFrameCount(Double(buf.frameLength) * ratio) + 16)!
        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buf
        }
        guard err == nil else { return [] }
        return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
    }
}
