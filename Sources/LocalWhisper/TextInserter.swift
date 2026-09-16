import AppKit
import Carbon.HIToolbox

/// Puts text on the pasteboard, sends ⌘V to the frontmost app, restores the previous clipboard.
@MainActor
enum TextInserter {
    /// nil when ⌘V was posted, else why it could not be. Whether the app accepted the paste is not observable.
    @discardableResult
    static func insert(_ text: String) -> String? {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        let wrote = pb.setString(text, forType: .string)
        let trusted = AXIsProcessTrusted(), canPost = CGPreflightPostEventAccess()
        NSLog("insert: ax_trusted=%d post_event_ok=%d pasteboard_wrote=%d chars=%d front=%@",
              trusted ? 1 : 0, canPost ? 1 : 0, wrote ? 1 : 0, text.count,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")

        // ponytail: fixed 300 ms restore; a pasteboard changeCount poll if slow apps drop the paste
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pb.clearContents()
                if let saved { pb.setString(saved, forType: .string) }
            }
        }

        guard trusted, canPost else { return "Accessibility permission missing" }
        guard wrote else { return "Clipboard is not writable" }
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return "Could not send ⌘V" }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return nil
    }
}
