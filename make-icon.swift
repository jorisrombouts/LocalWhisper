// Generates the app icon. Rebuild Resources/AppIcon.icns with:
//   swiftc -O make-icon.swift -o /tmp/icon && /tmp/icon /tmp/icon1024.png
//   mkdir -p /tmp/AppIcon.iconset && for s in 16 32 128 256 512; do sips -z $s $s /tmp/icon1024.png --out /tmp/AppIcon.iconset/icon_${s}x${s}.png; sips -z $((s*2)) $((s*2)) /tmp/icon1024.png --out /tmp/AppIcon.iconset/icon_${s}x${s}@2x.png; done
//   iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
import SwiftUI
import AppKit

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
