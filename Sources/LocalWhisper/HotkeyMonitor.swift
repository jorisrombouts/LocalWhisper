import AppKit

/// Hold Left Option to dictate; a tap (under 0.3 s) is reported separately for hands-free mode.
/// Any other key pressed during a hold cancels it, so Option-combos (€, @, accents) never trigger a dictation.
@MainActor
final class HotkeyMonitor {
    static let leftOptionKeyCode: UInt16 = 58
    static let escapeKeyCode: UInt16 = 53
    static let tapSeconds = 0.3

    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onCancel: () -> Void = {}
    var onTap: () -> Void = {}
    var onEscape: () -> Void = {}

    private var isHeld = false
    private var cancelled = false
    private var pressedAt = Date()
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
                isHeld = true; cancelled = false; pressedAt = Date()
                onPress()
            } else if !down, isHeld {
                isHeld = false
                if !cancelled { Date().timeIntervalSince(pressedAt) < Self.tapSeconds ? onTap() : onRelease() }
            }
        case .keyDown where isHeld && !cancelled:
            cancelled = true
            onCancel()
        case .keyDown where e.keyCode == Self.escapeKeyCode:
            onEscape()
        default:
            break
        }
    }
}
