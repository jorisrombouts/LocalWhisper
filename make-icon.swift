import SwiftUI
import AppKit

for n in ["waveform", "waveform.badge.mic", "waveform.badge.magnifyingglass"] {
    print(n, NSImage(systemSymbolName: n, accessibilityDescription: nil) != nil ? "ok" : "MISSING")
}

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 184, style: .continuous)   // Apple macOS icon grid: 824 pt square, 184 pt corners
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.30, blue: 0.95), Color(red: 0.13, green: 0.62, blue: 0.96)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(100)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 12)
            Image(systemName: "waveform")
                .font(.system(size: 520, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
        }
        .frame(width: 1024, height: 1024)
    }
}

MainActor.assumeIsolated {
let r = ImageRenderer(content: Icon())
r.scale = 1
let img = r.nsImage!
let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote", CommandLine.arguments[1])
}
