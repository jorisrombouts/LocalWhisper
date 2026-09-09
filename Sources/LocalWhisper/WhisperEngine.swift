import Accelerate
import Foundation
import whisper

/// Thin wrapper over whisper.h. Actor because a whisper_context is not thread-safe.
actor WhisperEngine {
    private let ctx: OpaquePointer
    private let language = strdup("auto")! // lives as long as the process

    init(modelPath: String) throws {
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        cparams.flash_attn = true
        guard let ctx = whisper_init_from_file_with_params(modelPath, cparams) else {
            throw NSError(domain: "WhisperEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load model at \(modelPath)"])
        }
        self.ctx = ctx
    }

    // Engine lives for the process lifetime; no deinit needed.

    /// A clip whose loudest 100 ms stays under this is silence: whisper answers silence with "Thank you." or "you".
    /// Measured: a silent hold peaks under 0.002; speech at 27% input volume peaks around 0.009, at normal volume 0.03 and up.
    /// ponytail: fixed threshold; calibrate from `peak=` in the log if quiet speech gets dropped
    static let silencePeak: Float = 0.005

    /// 16 kHz mono float samples in, text out.
    func transcribe(_ samples: [Float]) -> String {
        let window = 1600
        let peak = stride(from: 0, to: samples.count, by: window)
            .map { vDSP.rootMeanSquare(samples[$0..<min($0 + window, samples.count)]) }.max() ?? 0
        NSLog("whisper peak=%.4f", peak)
        guard peak >= Self.silencePeak else { return "" }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.language = UnsafePointer(language)
        params.n_threads = 4
        params.no_timestamps = true
        params.single_segment = false
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.suppress_blank = true
        params.suppress_nst = true

        let rc = samples.withUnsafeBufferPointer { buf in
            whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
        guard rc == 0 else { return "" }

        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            // Whisper hallucinates sentences on silence; drop segments it itself thinks are non-speech.
            guard whisper_full_get_segment_no_speech_prob(ctx, i) < 0.6 else { continue }
            if let c = whisper_full_get_segment_text(ctx, i) { text += String(cString: c) }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Punctuation-only output (e.g. ".") is silence, not speech.
        return text.contains(where: { $0.isLetter || $0.isNumber }) ? text : ""
    }

    func warmUp() {
        _ = transcribe([Float](repeating: 0, count: 16_000))
    }
}
