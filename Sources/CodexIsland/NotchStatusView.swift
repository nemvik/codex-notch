import AppKit
import SwiftUI

/// Uses only the drawable band between the hardware cutout and menu-bar bottom.
/// If no such band exists, the caller uses the native menu-bar fallback.
struct NotchGeometry: Equatable {
    let frame: CGRect
    let bandHeight: CGFloat
    let lineHeight: CGFloat
    let lineWidth: CGFloat

    init?(screen: CGRect, visible: CGRect, safeTop: CGFloat, left: CGRect?, right: CGRect?, scale: CGFloat) {
        guard safeTop > 0, let left, let right, !left.isEmpty, !right.isEmpty,
              right.minX > left.maxX else { return nil }
        let pixel = 1 / max(1, scale)
        let cameraBottom = screen.maxY - safeTop
        let barBottom = visible.maxY
        let band = cameraBottom - barBottom
        guard band >= pixel, band <= 8 else { return nil }
        let x = (left.maxX / pixel).rounded(.up) * pixel
        let end = (right.minX / pixel).rounded(.down) * pixel
        guard end - x >= 40 else { return nil }
        frame = CGRect(x: x, y: barBottom, width: end - x, height: screen.maxY - barBottom)
        bandHeight = band
        lineHeight = min(1.5, band)
        lineWidth = min(156, end - x - 24)
    }
}

struct NotchStatusView: View {
    @ObservedObject var model: IslandModel
    let geometry: NotchGeometry
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Capsule().fill(model.accent)
                    .frame(width: geometry.lineWidth, height: geometry.lineHeight)
                    .opacity(model.isConnected && model.activity.runningTasks + model.activity.runningSubagents + model.activity.waitingCount + model.activity.failureCount + model.activity.completionCount == 0 ? 0.25 : 0.85)
                    .padding(.bottom, (geometry.bandHeight - geometry.lineHeight) / 2)
            }
            .frame(width: geometry.frame.width, height: geometry.frame.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Codex Notch: \(model.headline). \(model.subtitle)")
        .accessibilityHint("Kliknutím otevřít počty a přehled chatů")
        .contextMenu {
            Button("Otevřít přehled", action: open)
            Button("Obnovit napojení") { model.reconnect() }
            Divider()
            Button("Ukončit Codex Notch") { NSApp.terminate(nil) }
        }
    }
}

final class NotchStatusPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
