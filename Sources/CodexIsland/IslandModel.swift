import AppKit
import SwiftUI
import ServiceManagement
import IslandCore

@MainActor
final class IslandModel: ObservableObject {
    @Published private(set) var activity = ActivityStore()
    @Published private(set) var connection: FeedConnection = .connecting
    @Published private(set) var connectionDetail = "Připojuji se ke Codexu…"
    @Published private(set) var catalogCount = 0
    @Published var settingsError: String?
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    var changed: (() -> Void)?
    var openThread: ((ThreadSummary) -> Void)?
    var closeOverview: (() -> Void)?
    private var feed: DesktopFeed?
    private var timer: Timer?
    let demo: Bool

    init(demo: Bool = false) { self.demo = demo }

    func start() {
        if demo {
            connection = .connected; connectionDetail = "Ukázková data · bez napojení na Codex"
            catalogCount = 3
            activity.update([
                ThreadSummary(id: "demo1", title: "Úprava přihlášení", phase: .running, detail: "Agent pracuje", startedAt: Date().addingTimeInterval(-240)),
                ThreadSummary(id: "demo2", title: "Nasazení webu", phase: .waiting, detail: "Potřebuje schválení"),
                ThreadSummary(id: "demo3", title: "Review pull requestu", phase: .running, detail: "Kontroluje změny", startedAt: Date().addingTimeInterval(-80), isSubagent: true)
            ])
        } else {
            feed = DesktopFeed(home: Self.codexHome) { [weak self] event in
                DispatchQueue.main.async { self?.receive(event) }
            }
            feed?.start()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.activity.expire(); self?.changed?() }
        }
    }

    static var codexHome: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    func stop() { feed?.stop(); timer?.invalidate() }
    func reconnect() { feed?.reconnect() }
    func acknowledge() { activity.acknowledge(); changed?() }

    private func receive(_ event: FeedEvent) {
        switch event {
        case .connection(let state, let detail):
            connection = state; connectionDetail = detail
            if state != .connected { activity.disconnect() }
        case .summaries(let summaries):
            if connection == .connected { activity.update(summaries) }
        case .catalogCount(let count): catalogCount = count
        }
        changed?()
    }

    func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { settingsError = "Spouštění po přihlášení: \(error.localizedDescription)" }
        changed?()
    }

    var isConnected: Bool { connection == .connected }
    var accent: Color {
        if !isConnected { return Color(white: 0.55) }
        if activity.waitingCount > 0 { return .orange }
        if activity.failureCount > 0 { return .red }
        if activity.completionCount > 0 { return .green }
        return activity.runningTasks + activity.runningSubagents > 0 ? Color(red: 0.42, green: 0.73, blue: 1) : Color(white: 0.55)
    }
    var headline: String {
        if demo { return "Ukázka Codex Notch" }
        if !isConnected { return connection == .connecting ? "Připojuji se" : "Codex je odpojený" }
        if activity.waitingCount > 0 { return "\(activity.waitingCount) čeká na tebe" }
        if activity.failureCount > 0 { return "Některá úloha potřebuje pozornost" }
        if activity.runningTasks + activity.runningSubagents > 0 { return "Agenti pracují" }
        if activity.completionCount > 0 { return "Výsledky jsou připravené" }
        return "Všechno v klidu"
    }
    var compactLabel: String {
        if !isConnected { return "" }
        if activity.waitingCount > 0 { return "\(activity.waitingCount)" }
        if activity.failureCount > 0 { return "\(activity.failureCount)" }
        if activity.completionCount > 0 { return "\(activity.completionCount)" }
        return ""
    }
    var compactSymbol: String {
        if !isConnected { return "link.badge.plus" }
        if activity.waitingCount > 0 { return "exclamationmark.bubble.fill" }
        if activity.failureCount > 0 { return "exclamationmark.triangle.fill" }
        if activity.completionCount > 0 { return "checkmark.circle.fill" }
        return activity.runningTasks + activity.runningSubagents > 0 ? "circle.fill" : "moon"
    }
    var subtitle: String {
        if !isConnected { return connectionDetail }
        func counted(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
            "\(count) \(count == 1 ? one : (2...4).contains(count) ? few : many)"
        }
        var parts: [String] = []
        if activity.runningTasks > 0 { parts.append(counted(activity.runningTasks, "úloha", "úlohy", "úloh")) }
        if activity.runningSubagents > 0 { parts.append(counted(activity.runningSubagents, "subagent", "subagenti", "subagentů")) }
        if activity.waitingCount > 0 { parts.append("\(activity.waitingCount) čeká na tebe") }
        return parts.isEmpty ? "Žádná běžící úloha" : parts.joined(separator: " · ")
    }
}
