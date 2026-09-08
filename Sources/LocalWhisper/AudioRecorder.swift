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
        let t0 = Date()
        // Always bind a concrete device. Leaving the engine on CoreAudio's per-process default aggregate
        // records silence after the default changes sample rate (AirPods 24 kHz vs built-in 48 kHz).
        // A fresh engine per press: reusing one across a device switch leaves it with a stale format and no audio.
        engine = AVAudioEngine()
        let input = engine.inputNode
        let uid = UserDefaults.standard.string(forKey: Settings.inputDeviceKey) ?? ""
        if var id = Self.deviceID(uid: uid) ?? Self.builtInID() ?? Self.defaultInputID() {
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
        NSLog("mic: %@ (%d Hz) started in %d ms", Self.inputDeviceName(input), Int(native.sampleRate), Int(Date().timeIntervalSince(t0) * 1000))
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

    static func defaultInputID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    static func transport(of id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport)
        return transport
    }

    /// Loopback drivers (Teams, Zoom) and CoreAudio's own aggregate devices show up as microphones; hide them.
    static func isVirtual(uid: String) -> Bool {
        guard let id = deviceID(uid: uid) else { return false }
        return [kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate].contains(transport(of: id))
    }

    /// The built-in microphone: instant to start and best for speech. Bluetooth headsets lose the first
    /// half second to their profile switch, so they are only used when picked explicitly.
    static func builtInID() -> AudioDeviceID? {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
            .compactMap { deviceID(uid: $0.uniqueID) }.first { transport(of: $0) == kAudioDeviceTransportTypeBuiltIn }
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
        NSLog("mic stopped: %.2f s", Double(out.count) / Self.sampleRate)
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
