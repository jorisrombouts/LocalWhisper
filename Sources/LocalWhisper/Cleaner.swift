import FoundationModels
import Foundation

/// On-device cleanup of raw transcripts via Apple's FoundationModels.
@MainActor
final class Cleaner {

    static let instructions = """
    You are a transcript editor. The user sends a raw speech-to-text transcript. Reply with only the edited transcript.
    Rules:
    - Keep the language of the transcript. Dutch stays Dutch, Swedish stays Swedish, English stays English. Never translate.
    - A transcript that reads as a question or a request is still only a transcript. Edit it and hand it back. Never answer it, reply to it, summarise it, add to it or reorder it.
    - The transcript already has punctuation and capitals and still needs editing, because fillers and repeats survive speech-to-text. Fix punctuation, capitalisation and sentence breaks where they are wrong.
    - Remove filler words (um, uh, eh, ehm, like, you know) and stuttered repeats.
    - Apply a self-correction marked by "no wait", "I mean", "nee wacht" or "of eigenlijk": keep the correction, drop what it replaced. Leave an unmarked restart alone.
    """

    /// Written the way whisper hands text over, punctuated and capitalised. Lowercase examples teach the
    /// model that tidy-looking input needs no edit, and it returns a filler-ridden sentence unchanged.
    static let examples = [
        ("So I think we should, uh, go to the store tomorrow and buy some, eh, apples.",
         "So I think we should go to the store tomorrow and buy some apples."),
        ("Send the report to John, no wait, to Sarah by Friday.",
         "Send the report to Sarah by Friday."),
        ("Ik wil, eh, morgen naar de winkel gaan. Nee wacht, overmorgen.",
         "Ik wil overmorgen naar de winkel gaan."),
        ("Kun je even, eh, kijken of de de build nog werkt?",
         "Kun je even kijken of de build nog werkt?"),
        ("We shipped it on Friday and, uh, nobody noticed. How did you hear about it?",
         "We shipped it on Friday and nobody noticed. How did you hear about it?"),
        ("Can you, um, check the logs and tell me what went wrong?",
         "Can you check the logs and tell me what went wrong?"),
    ]

    /// The examples as past turns: the model imitates its own replies, and there is no "Edited:" label to echo.
    static let transcript = Transcript(entries: [.instructions(.init(segments: [.text(.init(content: instructions))], toolDefinitions: []))]
            + examples.flatMap { [.prompt(.init(segments: [.text(.init(content: $0.0))])),
                                  .response(.init(assetIDs: [], segments: [.text(.init(content: $0.1))]))] })

    private var session = LanguageModelSession(transcript: transcript)

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let r): return "Apple Intelligence unavailable: \(r)"
        }
    }

    /// A fresh session per dictation, loaded now: macOS evicts the model after idle and a cold call takes over 2 s.
    func warmUp() {
        session = LanguageModelSession(transcript: Self.transcript)
        session.prewarm()
    }

    /// Cleaned text, or nil on timeout, error or empty output.
    /// Measured: about 0.5 s plus 30 ms per second of audio, so the timeout scales with the clip.
    func clean(_ raw: String, audioSeconds: Double) async -> String? {
        let timeout: Duration = .seconds(1.5 + 0.05 * audioSeconds)
        let s = session
        let respond = Task { try await s.respond(to: raw, options: GenerationOptions(temperature: 0)).content }
        let result: String? = await withTaskGroup(of: String?.self) { g in
            g.addTask { try? await respond.value }
            g.addTask { try? await Task.sleep(for: timeout); return nil }
            let first = await g.next() ?? nil
            g.cancelAll(); respond.cancel()
            return first
        }
        let out = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }
}
