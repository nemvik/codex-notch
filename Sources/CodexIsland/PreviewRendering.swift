import AppKit
import SwiftUI

/// Documentation assets use demo data and an explicitly illustrated desktop.
/// This does not capture the screen or connect to the user's Codex.
@MainActor
enum PreviewRendering {
    static func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = IslandModel(demo: true)
        model.start()
        defer { model.stop() }
        let presentation = IslandPresentation()
        presentation.rowCapacity = 3
        for expanded in [false, true] {
            let scene = PreviewScene(model: model, presentation: presentation, expanded: expanded)
                .environment(\.colorScheme, .light)
                .frame(width: 560, height: expanded ? 370 : 140)
            let renderer = ImageRenderer(content: scene)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw NSError(domain: "CodexIsland.Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render preview"])
            }
            try data.write(to: directory.appendingPathComponent(expanded ? "popover.png" : "notch.png"), options: .atomic)
        }
    }
}

private struct PreviewScene: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var presentation: IslandPresentation
    let expanded: Bool
    private let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 560, height: 400),
                                         visible: CGRect(x: 0, y: 0, width: 560, height: 366), safeTop: 32,
                                         left: CGRect(x: 0, y: 368, width: 190.5, height: 32),
                                         right: CGRect(x: 369.5, y: 368, width: 190.5, height: 32), scale: 2)!
    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.88, green: 0.91, blue: 0.94)
            HStack {
                Text("Codex Notch").font(.system(size: 11, weight: .semibold))
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
                Text("9:41")
            }
            .font(.system(size: 10)).foregroundStyle(Color.black.opacity(0.7))
            .padding(.horizontal, 18).frame(height: 34).background(.white.opacity(0.22))
            RoundedRectangle(cornerRadius: 12).fill(.black).frame(width: 179, height: 44).offset(y: -12)
            NotchStatusView(model: model, geometry: geometry, open: {}).frame(width: 179, height: 34)
            if expanded {
                IslandView(model: model, presentation: presentation, renderingPreview: true)
                    .frame(width: IslandLayout.width, height: IslandLayout.bodyHeight(capacity: 3))
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
                    .padding(.top, 52)
            }
        }
        .clipped()
        .overlay(alignment: .bottom) {
            Text("Illustrated desktop · demo data").font(.system(size: 9))
                .foregroundStyle(.black.opacity(0.35)).padding(.bottom, 12)
        }
    }
}
