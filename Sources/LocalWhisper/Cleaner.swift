import FoundationModels
import Foundation

/// On-device cleanup of raw transcripts via Apple's FoundationModels.
@MainActor
final class Cleaner {

    static let instructions = """
    You are a transcript editor. The user sends a raw speech-to-text transcript. Reply with only the edited transcript.
    Rules:
    - Keep the language of the transcript. Dutch stays Dutch, Swedish stays Swedish, English stays English. Never translate.
    - Keep the speaker's words and meaning. Never answer, reply, summarise, add or reorder content.
    - Fix punctuation, capitalisation and sentence breaks.
    - Remove filler words (um, uh, eh, ehm, like, you know) and stuttered repeats.
    - Apply self-corrections ("no wait", "I mean", "nee wacht", "of eigenlijk"): keep the correction, drop what it replaced.
    """

    static let examples = [
        ("um so i think we should uh go to the the store tomorrow", "I think we should go to the store tomorrow."),
        ("send the report to john no wait to sarah by friday", "Send the report to Sarah by Friday."),
        ("ik wil eh morgen naar de winkel gaan nee wacht overmorgen", "Ik wil overmorgen naar de winkel gaan."),
        ("kun je even eh kijken of de de build nog werkt", "Kun je even kijken of de build nog werkt?"),
    ]

    /// The examples as past turns: the model imitates its own replies, and there is no "Edited:" label to echo.
    static var transcript: Transcript {
        Transcript(entries: [.instructions(.init(segments: [.text(.init(content: instructions))], toolDefinitions: []))]
            + examples.flatMap { [.prompt(.init(segments: [.text(.init(content: $0.0))])),
                                  .response(.init(assetIDs: [], segments: [.text(.init(content: $0.1))]))] })
    }

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
