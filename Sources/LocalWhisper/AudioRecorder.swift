import AVFoundation
import CoreAudio

/// AVCaptureSession on the chosen microphone -> 16 kHz mono Float samples. RMS level per buffer via `onLevel` (audio thread).
/// AVCaptureSession is the API for recording from a specific device; binding a device onto AVAudioEngine's
/// input node breaks on Bluetooth headsets, which renegotiate their sample rate right after the mic opens.
final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let minSeconds = 0.4
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    var onLevel: (@Sendable (Float) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?

    override init() {
        super.init()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "LocalWhisper.audio"))
        session.addOutput(output)
    }

    static func inputDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
            .filter { ![kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate].contains(transport(of: $0)) }   // Teams/Zoom loopbacks, CoreAudio aggregates
    }

    /// The picked device, else the built-in mic (instant, best for speech; Bluetooth headsets lose the first
    /// half second to their profile switch), else the system default.
    static func device() -> AVCaptureDevice? {
        let uid = UserDefaults.standard.string(forKey: Settings.inputDeviceKey) ?? ""
        let all = inputDevices()
        return all.first { $0.uniqueID == uid } ?? all.first { transport(of: $0) == kAudioDeviceTransportTypeBuiltIn } ?? AVCaptureDevice.default(for: .audio)
    }

    func start() throws {
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        let t0 = Date()
        guard let device = Self.device() else { throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone"]) }
        session.inputs.forEach(session.removeInput)
        session.addInput(try AVCaptureDeviceInput(device: device))
        converter = nil
        session.startRunning()
        NSLog("mic: %@ started in %d ms", device.localizedName, Int(Date().timeIntervalSince(t0) * 1000))
    }

    /// Returns the samples, or nil when the clip is too short to be worth transcribing.
    func stop() -> [Float]? {
        session.stopRunning()
        let out = lock.withLock { samples }
        let seconds = Double(out.count) / Self.format.sampleRate
        NSLog("mic stopped: %.2f s", seconds)
        return seconds < Self.minSeconds ? nil : out
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard var asbd = CMSampleBufferGetFormatDescription(sb)?.audioStreamBasicDescription,
              let fmt = AVAudioFormat(streamDescription: &asbd),
              let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sb))) else { return }
        pcm.frameLength = pcm.frameCapacity
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sb, at: 0, frameCount: Int32(pcm.frameLength), into: pcm.mutableAudioBufferList) == noErr else { return }
        if converter?.inputFormat != fmt { converter = AVAudioConverter(from: fmt, to: Self.format) }   // the first buffer after a device switch can still carry the old format
        guard let converter else { return }
        let chunk = Self.resample(pcm, with: converter)
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

    /// CoreAudio transport type (built-in, Bluetooth, USB, virtual, aggregate) of an AVCaptureDevice.
    private static func transport(of device: AVCaptureDevice) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var cf = device.uniqueID as CFString
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard withUnsafePointer(to: &cf, { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<CFString>.size), $0, &size, &id) }) == noErr else { return 0 }
        addr.mSelector = kAudioDevicePropertyTransportType
        var transport = UInt32(0)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport)
        return transport
    }
}
