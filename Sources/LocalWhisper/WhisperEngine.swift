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

    /// 16 kHz mono float samples in, text out.
    func transcribe(_ samples: [Float]) -> String {
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
            if let c = whisper_full_get_segment_text(ctx, i) { text += String(cString: c) }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func warmUp() {
        _ = transcribe([Float](repeating: 0, count: 16_000))
    }
}
