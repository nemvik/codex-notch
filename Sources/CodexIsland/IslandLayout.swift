import SwiftUI
import IslandCore

enum IslandLayout {
    static let width: CGFloat = 336
    static let rowHeight: CGFloat = 48
    static let rowSpacing: CGFloat = 2
    static let maximumRows = 3
    static func listHeight(capacity: Int) -> CGFloat {
        CGFloat(capacity) * rowHeight + CGFloat(max(0, capacity - 1)) * rowSpacing
    }
    static func bodyHeight(capacity: Int) -> CGFloat { 105 + listHeight(capacity: capacity) }
}

struct IslandIndicator: Equatable {
    let symbol: String
    let title: String

    init(activity: ActivityStore, connected: Bool) {
        guard connected else { symbol = "link.badge.plus"; title = ""; return }
        let running = activity.runningTasks + activity.runningSubagents
        let count: Int
        if activity.waitingCount > 0 {
            symbol = "exclamationmark.bubble"; count = activity.waitingCount
        } else if activity.failureCount > 0 {
            symbol = "exclamationmark.triangle"; count = activity.failureCount
        } else if activity.completionCount > 0 {
            symbol = "checkmark.circle"; count = activity.completionCount
        } else {
            symbol = running > 0 ? "sparkle" : "moon"; count = running
        }
        title = count == 0 ? "" : count > 99 ? "99+" : String(count)
    }
}

@MainActor
final class IslandPresentation: ObservableObject {
    @Published var rowCapacity = 2
}
