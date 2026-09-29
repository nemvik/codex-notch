import AppKit
import SwiftUI
import IslandCore

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var presentation: IslandPresentation
    var renderingPreview = false

    var body: some View {
        detail
            .frame(width: IslandLayout.width)
            .foregroundStyle(.primary)
            .onExitCommand { model.closeOverview?() }
            .alert("Codex Notch", isPresented: Binding(get: { model.settingsError != nil }, set: { if !$0 { model.settingsError = nil } })) {
                Button("OK") { model.settingsError = nil }
            } message: { Text(model.settingsError ?? "") }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Codex Notch").font(.system(size: 14, weight: .semibold))
                    Text(model.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                if renderingPreview {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary).frame(width: 26, height: 26)
                } else {
                    Menu {
                        Button(model.loginEnabled ? "Vypnout spuštění po přihlášení" : "Spouštět po přihlášení") { model.toggleLogin() }
                        Button("Zavřít přehled") { model.closeOverview?() }
                        Divider()
                        Button("Ukončit Codex Notch") { NSApplication.shared.terminate(nil) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary).frame(width: 26, height: 26)
                            .contentShape(Circle())
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Nastavení").accessibilityLabel("Nastavení Codex Notch")
                }
            }
            .padding(.horizontal, 10).frame(height: 42)

            Rectangle().fill(.primary.opacity(0.12)).frame(height: 0.5).padding(.horizontal, 10)

            Group {
                if model.isConnected, !model.activity.visible.isEmpty {
                    if renderingPreview {
                        VStack(spacing: IslandLayout.rowSpacing) {
                            ForEach(model.activity.visible.prefix(presentation.rowCapacity), id: \.key) { row in
                                ThreadRow(row: row) {}
                            }
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: IslandLayout.rowSpacing) {
                                ForEach(model.activity.visible, id: \.key) { row in
                                    ThreadRow(row: row) { model.openThread?(row) }
                                }
                            }
                        }.scrollIndicators(.hidden)
                    }
                } else {
                    emptyState
                }
            }
            .frame(height: IslandLayout.listHeight(capacity: presentation.rowCapacity))
            .padding(.top, 7)

            HStack(spacing: 6) {
                Circle().fill(model.isConnected ? Color.green.opacity(0.8) : Color.gray).frame(width: 4, height: 4)
                Text(model.demo ? "Ukázkový přehled" : model.isConnected ? "Připojeno k tomuto Macu" : "Čekám na připojení")
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                Spacer()
                Button { model.reconnect() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary).frame(width: 26, height: 26).contentShape(Circle())
                }.buttonStyle(IslandButtonStyle()).help("Obnovit napojení").accessibilityLabel("Obnovit napojení")
            }
            .padding(.horizontal, 10).frame(height: 30)
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 15.5)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.isConnected ? "moon" : "personalhotspot")
                .font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
            Text(model.isConnected ? "Žádná aktivní úloha" : "Čekám na desktopový Codex")
                .font(.system(size: 12, weight: .medium))
            Text(model.isConnected ? "Až se něco rozběhne, uvidíš to tady." : "Po spuštění se připojí automaticky.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ThreadRow: View {
    let row: ThreadSummary
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        switch row.phase {
        case .running: return Color(red: 0.42, green: 0.73, blue: 1)
        case .waiting: return .orange
        case .failed: return .red
        case .completed: return .green
        default: return .gray
        }
    }
    private var symbol: String {
        switch row.phase {
        case .running: return row.isSubagent ? "arrow.triangle.branch" : "sparkle"
        case .waiting: return "exclamationmark.bubble"
        case .failed: return "exclamationmark.triangle"
        case .completed: return "checkmark"
        default: return "moon"
        }
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color).frame(width: 28, height: 28)
                    .background(color.opacity(0.09), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text((row.detail.isEmpty ? row.phase.label : row.detail) + (row.isSubagent ? " · subagent" : ""))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if row.phase == .running, let started = row.startedAt {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(elapsed(since: started, at: context.date))
                            .font(.system(size: 10)).monospacedDigit().foregroundStyle(.tertiary)
                    }.frame(width: 38, alignment: .trailing)
                }
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(hovered ? 1 : 0.5))
            }
            .padding(.horizontal, 10).frame(height: IslandLayout.rowHeight)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(IslandButtonStyle())
        .onHover { value in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { hovered = value }
        }
        .help("Otevřít chat: \(row.title)")
    }

    private func elapsed(since start: Date, at now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        if minutes < 1 { return "teď" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h"
    }
}

private struct IslandButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        HoverSurface(configuration: configuration, reduceMotion: reduceMotion)
    }

    private struct HoverSurface: View {
        let configuration: ButtonStyle.Configuration
        let reduceMotion: Bool
        @State private var hovered = false
        var body: some View {
            configuration.label
                .background(.primary.opacity(configuration.isPressed ? 0.1 : hovered ? 0.055 : 0),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onHover { hovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}
