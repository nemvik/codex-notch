import AppKit
import IslandCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: IslandController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = IslandModel(demo: CommandLine.arguments.contains("--demo"))
        controller = IslandController(model: model)
        model.start()
        if CommandLine.arguments.contains("--expanded") { controller?.showOverview() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showOverview()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { controller?.stop() }
}

@main
enum CodexIslandApp {
    @MainActor
    static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews") {
            guard CommandLine.arguments.indices.contains(index + 1) else {
                fputs("Usage: CodexIsland --render-previews <directory>\n", stderr)
                exit(2)
            }
            _ = NSApplication.shared
            do {
                try PreviewRendering.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
            } catch {
                fputs("Preview rendering failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        // A bounded, content-free integration check using the same transport as the UI.
        if CommandLine.arguments.contains("--diagnose") {
            let home = IslandModel.codexHome
            var connected = false
            var received = false
            var latest: [ThreadSummary] = []
            var count = 0
            let feed = DesktopFeed(home: home) { event in
                DispatchQueue.main.async {
                    switch event {
                    case .connection(let state, let reason):
                        connected = state == .connected
                        print("connection=\(state.rawValue) detail=\(reason)")
                    case .catalogCount(let value): count = value
                    case .summaries(let rows):
                        if !rows.isEmpty { received = true }
                        latest = rows
                    }
                }
            }
            feed.start()
            RunLoop.main.run(until: Date().addingTimeInterval(10))
            let tasks = latest.filter { $0.phase == .running && !$0.isSubagent }.count
            let subagents = latest.filter { $0.phase == .running && $0.isSubagent }.count
            let waiting = latest.filter { $0.phase == .waiting }.count
            print("catalog=\(count) liveSnapshots=\(latest.count) runningTasks=\(tasks) runningSubagents=\(subagents) waiting=\(waiting)")
            feed.stop()
            exit(connected && received ? 0 : 1)
        } else {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}
