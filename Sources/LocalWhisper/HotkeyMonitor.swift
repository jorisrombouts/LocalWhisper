import AppKit

/// Hold Left Option to dictate. Any other key pressed during the hold cancels it,
/// so Option-combos (€, @, accents) never trigger a dictation.
@MainActor
final class HotkeyMonitor {
    static let leftOptionKeyCode: UInt16 = 58

    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onCancel: () -> Void = {}

    private var isHeld = false
    private var cancelled = false
    private var monitors: [Any] = []

    static func ensureAccessibility(prompt: Bool) -> Bool {
        let opts = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    func start() {
        let handle: (NSEvent) -> Void = { [weak self] e in self?.handle(e) }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handle) as Any,
            NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { e in handle(e); return e } as Any,
        ]
    }

    private func handle(_ e: NSEvent) {
        switch e.type {
        case .flagsChanged where e.keyCode == Self.leftOptionKeyCode:
            let down = e.modifierFlags.contains(.option)
            if down, !isHeld {
                isHeld = true; cancelled = false
                onPress()
            } else if !down, isHeld {
                isHeld = false
                cancelled ? () : onRelease()
            }
        case .keyDown where isHeld && !cancelled:
            cancelled = true
            onCancel()
        default:
            break
        }
    }
}
