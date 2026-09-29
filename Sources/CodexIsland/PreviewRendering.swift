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
        for phase in [NotchPhase.resting, .revealed, .expanded] {
            presentation.notchPhase = phase
            let expanded = phase == .expanded
            let scene = PreviewScene(model: model, presentation: presentation, expanded: expanded)
                .environment(\.colorScheme, .light)
                .frame(width: 560, height: expanded ? 370 : 140)
            let renderer = ImageRenderer(content: scene)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw NSError(domain: "CodexIsland.Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render preview"])
            }
            try data.write(to: directory.appendingPathComponent(expanded ? "popover.png" : phase == .revealed ? "reveal.png" : "notch.png"), options: .atomic)
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
            NotchSurfaceView(model: model, presentation: presentation, geometry: geometry, toggle: {}, renderingPreview: true)
                .frame(width: geometry.surfaceFrame(phase: presentation.notchPhase, capacity: 3).width,
                       height: geometry.surfaceFrame(phase: presentation.notchPhase, capacity: 3).height)

        }
        .clipped()
        .overlay(alignment: .bottom) {
            Text("Illustrated desktop · demo data").font(.system(size: 9))
                .foregroundStyle(.black.opacity(0.35)).padding(.bottom, 12)
        }
    }
}
