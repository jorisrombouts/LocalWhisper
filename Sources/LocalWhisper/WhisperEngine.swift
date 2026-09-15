import Accelerate
import Foundation
import whisper

/// Thin wrapper over whisper.h. Actor because a whisper_context is not thread-safe.
actor WhisperEngine {
    private let ctx: OpaquePointer
    private let vadPath: UnsafeMutablePointer<CChar>?

    /// Silero VAD, the version whisper.cpp v1.9.2 ships support for (`models/download-vad-model.sh silero-v6.2.0`).
    static let vadModel = "ggml-silero-v6.2.0"

    init(modelPath: String, vadPath: String?) throws {
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        cparams.flash_attn = true
        guard let ctx = whisper_init_from_file_with_params(modelPath, cparams) else {
            throw NSError(domain: "WhisperEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load model at \(modelPath)"])
        }
        self.ctx = ctx
        self.vadPath = vadPath.map { strdup($0) }   // outlives every whisper_full call
    }

    // Engine lives for the process lifetime; no deinit needed.

    /// 16 kHz mono float samples in, text out.
    func transcribe(_ samples: [Float]) -> String {
        let window = 1600
        let peak = stride(from: 0, to: samples.count, by: window)
            .map { vDSP.rootMeanSquare(samples[$0..<min($0 + window, samples.count)]) }.max() ?? 0
        NSLog("whisper peak=%.4f", peak)   // mic diagnostics: distinguishes a dead mic from one VAD heard no speech on
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.language = nil        // auto-detect
        params.n_threads = 4
        params.no_timestamps = true
        params.suppress_blank = true
        params.suppress_nst = true
        // Silero VAD: only speech reaches the decoder, so non-speech has nothing to hallucinate from.
        if let vadPath {
            params.vad = true
            params.vad_model_path = UnsafePointer(vadPath)
            params.vad_params = whisper_vad_default_params()
        }

        let rc = samples.withUnsafeBufferPointer { buf in
            whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
        guard rc == 0 else { return "" }

        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
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
