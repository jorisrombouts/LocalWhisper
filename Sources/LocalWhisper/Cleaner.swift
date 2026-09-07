import FoundationModels
import Foundation

/// On-device cleanup of raw transcripts via Apple's FoundationModels.
@MainActor
final class Cleaner {
    static let timeout: Duration = .seconds(1.5)

    static let instructions = """
    You are a transcript editor. The user sends a raw speech-to-text transcript. Reply with only the edited transcript.
    Rules:
    - Keep the language of the transcript. Dutch stays Dutch, Swedish stays Swedish, English stays English. Never translate.
    - Keep the speaker's words and meaning. Never answer, reply, summarise, add or reorder content.
    - Fix punctuation, capitalisation and sentence breaks.
    - Remove filler words (um, uh, eh, ehm, like, you know) and stuttered repeats.
    - Apply self-corrections ("no wait", "I mean", "nee wacht", "of eigenlijk"): keep the correction, drop what it replaced.

    Transcript: um so i think we should uh go to the the store tomorrow
    Edited: I think we should go to the store tomorrow.

    Transcript: send the report to john no wait to sarah by friday
    Edited: Send the report to Sarah by Friday.

    Transcript: ik wil eh morgen naar de winkel gaan nee wacht overmorgen
    Edited: Ik wil overmorgen naar de winkel gaan.

    Transcript: kun je even eh kijken of de de build nog werkt
    Edited: Kun je even kijken of de build nog werkt?
    """

    private var session = LanguageModelSession(instructions: instructions)

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let r): return "Apple Intelligence unavailable: \(r)"
        }
    }

    func warmUp() async {
        _ = try? await session.respond(to: "Transcript: hello there how are you", options: GenerationOptions(temperature: 0))
    }

    /// Cleaned text, or nil on timeout, error or empty output.
    func clean(_ raw: String) async -> String? {
        if session.isResponding { session = LanguageModelSession(instructions: Self.instructions) }
        let s = session
        let respond = Task { try await s.respond(to: "Transcript: " + raw, options: GenerationOptions(temperature: 0)).content }
        let result: String? = await withTaskGroup(of: String?.self) { g in
            g.addTask { try? await respond.value }
            g.addTask { try? await Task.sleep(for: Self.timeout); return nil }
            let first = await g.next() ?? nil
            g.cancelAll(); respond.cancel()
            return first
        }
        let out = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }
}
