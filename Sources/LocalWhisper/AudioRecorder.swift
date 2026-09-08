import AVFoundation
import CoreAudio

/// AVAudioEngine tap -> 16 kHz mono Float samples. RMS level per buffer via `onLevel` (audio thread).
final class AudioRecorder: @unchecked Sendable {
    static let sampleRate = 16_000.0
    static let minSeconds = 0.4

    var onLevel: (@Sendable (Float) -> Void)?

    private var engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    func start() throws {
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        engine = AVAudioEngine()   // a fresh engine binds to the current default input (lid closed, dock, headset)
        let input = engine.inputNode
        if let uid = UserDefaults.standard.string(forKey: Settings.inputDeviceKey), var id = Self.deviceID(uid: uid) {
            AudioUnitSetProperty(input.audioUnit!, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let native = input.outputFormat(forBus: 0)
        guard native.sampleRate > 0 else { throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No input device"]) }
        converter = AVAudioConverter(from: native, to: Self.format)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: native) { [weak self] buf, _ in
            self?.consume(buf)
        }
        engine.prepare()
        try engine.start()
        NSLog("mic: %@ (%d Hz)", Self.inputDeviceName(input), Int(native.sampleRate))
    }

    /// CoreAudio device id for a device UID, nil when that device is not connected (then the default is used).
    static func deviceID(uid: String) -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var cf = uid as CFString
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: &cf) { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<CFString>.size), $0, &size, &id) }
        return status == noErr && id != 0 ? id : nil
    }

    private static func inputDeviceName(_ input: AVAudioInputNode) -> String {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioUnitGetProperty(input.audioUnit!, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, &size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var nsize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &nsize, &name)
        return name?.takeRetainedValue() as String? ?? "?"
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
