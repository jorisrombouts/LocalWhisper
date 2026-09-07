import AppKit
import Carbon.HIToolbox

/// Puts text on the pasteboard, sends ⌘V to the frontmost app, restores the previous clipboard.
@MainActor
enum TextInserter {
    static func insert(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        let wrote = pb.setString(text, forType: .string)
        NSLog("insert: ax_trusted=%d post_event_ok=%d pasteboard_wrote=%d chars=%d front=%@",
              AXIsProcessTrusted() ? 1 : 0, CGPreflightPostEventAccess() ? 1 : 0, wrote ? 1 : 0, text.count,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")

        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        // ponytail: fixed 300 ms restore; a pasteboard changeCount poll if slow apps drop the paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pb.clearContents()
            if let saved { pb.setString(saved, forType: .string) }
        }
    }
}
