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

enum NotchPhase { case resting, revealed, expanded }

extension NotchGeometry {
    /// An observation region, never an invisible window over application controls.
    var approachFrame: CGRect {
        CGRect(x: frame.minX, y: frame.minY - 12, width: frame.width, height: frame.height + 12)
    }

    func bodyFrame(phase: NotchPhase, capacity: Int) -> CGRect {
        let full = surfaceFrame(phase: phase, capacity: capacity)
        return CGRect(x: full.minX, y: full.minY, width: full.width, height: full.height - frame.height)
    }

    func surfaceFrame(phase: NotchPhase, capacity: Int) -> CGRect {
        let width = phase == .expanded ? IslandLayout.width : frame.width
        let extra: CGFloat = phase == .resting ? 0 : phase == .revealed ? 32 : IslandLayout.bodyHeight(capacity: capacity)
        return CGRect(x: frame.midX - width / 2, y: frame.minY - extra, width: width, height: frame.height + extra)
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
                    .opacity(model.isConnected && model.activity.visible.isEmpty ? 0.25 : 0.85)
                    .padding(.bottom, (geometry.bandHeight - geometry.lineHeight) / 2)
            }
            .frame(width: geometry.frame.width, height: geometry.frame.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Codex Notch: \(model.headline). \(model.subtitle)")
        .accessibilityHint("Najeďte k notchi nebo klikněte pro přehled")
    }
}

struct NotchAnchorView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var presentation: IslandPresentation
    let geometry: NotchGeometry
    let toggle: () -> Void
    var body: some View {
        if presentation.notchPhase == .resting {
            NotchStatusView(model: model, geometry: geometry, open: toggle)
        } else {
            Button(action: toggle) { Color.black.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .frame(width: geometry.frame.width, height: geometry.frame.height)
                .accessibilityLabel(presentation.notchPhase == .expanded ? "Zavřít přehled Codex" : "Otevřít přehled Codex")
        }
    }
}

/// One surface anchored to the physical camera. Only deliberate interaction
/// gives it a body below the menu bar; there are no wings over menu items.
struct NotchSurfaceView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var presentation: IslandPresentation
    let geometry: NotchGeometry
    let toggle: () -> Void
    var renderingPreview = false
    var includesAnchor = true

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if presentation.notchPhase != .resting {
                    NotchSurfaceShape(cameraWidth: geometry.frame.width, barHeight: includesAnchor ? geometry.frame.height : 0)
                        .fill(.black)
                }
                if presentation.notchPhase == .resting, includesAnchor {
                    NotchStatusView(model: model, geometry: geometry, open: toggle)
                } else if presentation.notchPhase != .resting {
                    VStack(spacing: 0) {
                        if includesAnchor {
                            Button(action: toggle) { Color.clear.contentShape(Rectangle()) }
                                .buttonStyle(.plain)
                                .frame(width: geometry.frame.width, height: geometry.frame.height)
                                .accessibilityLabel(presentation.notchPhase == .expanded ? "Zavřít přehled Codex" : "Otevřít přehled Codex")
                        }
                        if presentation.notchPhase == .revealed {
                            Button(action: toggle) {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkle").foregroundStyle(model.accent)
                                    Text("Codex").fontWeight(.medium)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                                }
                                .font(.system(size: 12))
                                .padding(.horizontal, 20)
                                .frame(width: geometry.frame.width, height: 32)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Otevřít přehled Codex")
                        } else {
                            IslandView(model: model, presentation: presentation, renderingPreview: renderingPreview)
                                .frame(width: IslandLayout.width, height: IslandLayout.bodyHeight(capacity: presentation.rowCapacity))
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
        }
        .environment(\.colorScheme, .dark)
        .onExitCommand { model.closeOverview?() }
    }
}

struct NotchSurfaceShape: Shape {
    let cameraWidth: CGFloat
    let barHeight: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bodyHeight = max(0, rect.height - barHeight)
        // The overlap joins the two pieces without an arrow or a visible seam.
        path.addRect(CGRect(x: rect.midX - cameraWidth / 2, y: 0, width: cameraWidth,
                            height: barHeight + min(18, bodyHeight)))
        if bodyHeight > 0 {
            path.addRoundedRect(in: CGRect(x: 0, y: barHeight, width: rect.width, height: bodyHeight),
                                cornerSize: CGSize(width: 18, height: 18))
        }
        return path
    }
}

final class NotchStatusPanel: NSPanel {
    var acceptsKeyboard = false
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
}

/// The notch must respond to the first click even while another app is active.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
