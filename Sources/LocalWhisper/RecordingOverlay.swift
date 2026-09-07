import AppKit
import SwiftUI

/// Floating, non-activating HUD pill at the bottom-centre of the screen under the mouse.
@MainActor
final class RecordingOverlay {
    private let panel: NSPanel
    private let hosting: NSHostingView<OverlayView>

    init(controller: DictationController) {
        hosting = NSHostingView(rootView: OverlayView(controller: controller))
        hosting.sizingOptions = [.preferredContentSize]
        panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
    }

    func show() {
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + 80, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()   // never makeKey: focus must stay in the target app
    }

    func hide() { panel.orderOut(nil) }
}

struct OverlayView: View {
    let controller: DictationController

    var body: some View {
        HStack(spacing: 10) {
            icon
            label
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(12)
        .animation(.easeOut(duration: 0.08), value: controller.level)
        .animation(.spring(duration: 0.25), value: controller.state)
    }

    @ViewBuilder private var icon: some View {
        switch controller.state {
        case .listening:
            Image(systemName: "mic.fill").foregroundStyle(.red)
            LevelBars(level: controller.level)
        case .transcribing:
            Image(systemName: "waveform").symbolEffect(.variableColor.iterative)
            ProgressView().controlSize(.small)
        case .cleaning:
            Image(systemName: "sparkles")
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark").foregroundStyle(.green)
        case .fallback:
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }

    private var label: some View {
        Text(text).font(.system(size: 13, weight: .medium)).monospacedDigit()
    }

    private var text: String {
        switch controller.state {
        case .idle: ""
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .cleaning: "Cleaning up"
        case .done: "Inserted"
        case .fallback(let s): s
        }
    }
}

struct LevelBars: View {
    let level: Float
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<6, id: \.self) { i in
                // Spread the single RMS value across bars with a per-bar weight so they move differently.
                let weight = [0.6, 0.9, 1.0, 1.0, 0.8, 0.5][i]
                Capsule()
                    .fill(.primary)
                    .frame(width: 3, height: 4 + CGFloat(min(1, Double(level) * 12) * weight) * 14)
            }
        }
        .frame(height: 18)
    }
}
