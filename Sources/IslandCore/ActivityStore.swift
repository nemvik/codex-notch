import Foundation

public struct ActivityStore {
    public private(set) var current: [String: ThreadSummary] = [:]
    public private(set) var finished: [String: ThreadSummary] = [:]
    public private(set) var unread: Set<String> = []
    private var finishedAt: [String: Date] = [:]
    public init() {}

    public mutating func update(_ summaries: [ThreadSummary], now: Date = Date()) {
        let next = Dictionary(summaries.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        for (key, summary) in next {
            if [.running, .waiting].contains(summary.phase) ||
                (finished[key] != nil && finished[key]?.turnID != summary.turnID) {
                finished.removeValue(forKey: key); finishedAt.removeValue(forKey: key); unread.remove(key)
            }
            guard let previous = current[key] else { continue } // Initial snapshots are a baseline, never notifications.
            if [.running, .waiting].contains(previous.phase),
                      [.idle, .failed].contains(summary.phase), summary.turnID == previous.turnID {
                var result = summary
                result.phase = summary.phase == .failed ? .failed : .completed
                // An interrupted turn is not a successful completion.
                if summary.detail == "Přerušeno" { continue }
                result.detail = result.phase == .completed ? "Výsledek je připravený" : summary.detail
                finished[key] = result; finishedAt[key] = now; unread.insert(key)
            }
        }
        current = next
        expire(now: now)
    }

    public mutating func disconnect() { current.removeAll() }
    public mutating func acknowledge() { unread.removeAll() }
    public mutating func expire(now: Date = Date()) {
        let expired = finishedAt.filter { now.timeIntervalSince($0.value) > 600 }.map(\.key)
        for key in expired { finished.removeValue(forKey: key); finishedAt.removeValue(forKey: key); unread.remove(key) }
    }
    public var runningTasks: Int { current.values.filter { $0.phase == .running && !$0.isSubagent }.count }
    public var runningSubagents: Int { current.values.filter { $0.phase == .running && $0.isSubagent }.count }
    public var waitingCount: Int { current.values.filter { $0.phase == .waiting }.count }
    public var failureCount: Int { finished.values.filter { $0.phase == .failed && unread.contains($0.key) }.count }
    public var completionCount: Int { finished.values.filter { $0.phase == .completed && unread.contains($0.key) }.count }

    public var visible: [ThreadSummary] {
        let active = current.values.filter { [.running, .waiting].contains($0.phase) }
        var rows = Array(active) + finished.values.filter { row in !active.contains { $0.key == row.key } }
        if rows.isEmpty {
            rows = Array(current.values.filter { $0.phase != .unknown && !$0.isSubagent }
                .sorted { $0.updatedAt > $1.updatedAt }.prefix(4))
        }
        let rank: [ThreadPhase: Int] = [.waiting: 0, .running: 1, .failed: 2, .completed: 3, .idle: 4, .unknown: 5]
        return rows.sorted {
            if rank[$0.phase] != rank[$1.phase] { return rank[$0.phase, default: 5] < rank[$1.phase, default: 5] }
            return $0.updatedAt > $1.updatedAt
        }
    }
}
