import Foundation

public enum ThreadPhase: String, Codable, Sendable {
    case running, waiting, idle, completed, failed, unknown
    public var label: String {
        switch self {
        case .running: return "Pracuje"
        case .waiting: return "Čeká na tebe"
        case .idle: return "V klidu"
        case .completed: return "Dokončeno"
        case .failed: return "Chyba"
        case .unknown: return "Stav neznámý"
        }
    }
}

public struct ThreadSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let hostID: String
    public var title: String
    public var phase: ThreadPhase
    public var detail: String
    public var updatedAt: Date
    public var startedAt: Date?
    public var isSubagent: Bool
    public var parentID: String?
    public var turnID: String?
    public var key: String { hostID + ":" + id }

    public init(id: String, hostID: String = "local", title: String, phase: ThreadPhase,
                detail: String = "", updatedAt: Date = Date(), startedAt: Date? = nil,
                isSubagent: Bool = false, parentID: String? = nil, turnID: String? = nil) {
        self.id = id; self.hostID = hostID; self.title = title; self.phase = phase
        self.detail = detail; self.updatedAt = updatedAt; self.startedAt = startedAt
        self.isSubagent = isSubagent; self.parentID = parentID; self.turnID = turnID
    }
}

/// Retain metadata only. Conversation text, tool output, secrets and file diffs are discarded.
public struct ThreadProjection {
    private static let scalarKeys: Set<String> = ["id", "title", "cwd", "threadRuntimeStatus", "updatedAt",
        "agentNickname", "threadSource", "source", "parentThreadId", "currentPermissions", "resumeState"]
    private var state: JSONValue
    public private(set) var revision: Int
    public var isCompatible: Bool {
        ["active", "idle", "notLoaded", "systemError"].contains(state["threadRuntimeStatus"]["type"].string ?? "")
    }

    public init(snapshot: JSONValue, revision: Int) {
        self.state = Self.project(snapshot)
        self.revision = revision
    }

    private static func projectTurn(_ turn: JSONValue) -> JSONValue {
        .object(turn.object.filter { ["status", "turnId", "turnStartedAtMs", "error"].contains($0.key) })
    }

    private static func project(_ value: JSONValue) -> JSONValue {
        var fields = value.object.filter { scalarKeys.contains($0.key) }
        fields["requests"] = .array(value["requests"].array.map { request in
            .object(request.object.filter { ["id", "method"].contains($0.key) })
        })
        fields["turns"] = .array(value["turns"].array.map(projectTurn))
        let entities = value["turnHistory"]["history"]["entitiesByKey"].object.mapValues(projectTurn)
        fields["turnHistory"] = .object(["history": .object(["entitiesByKey": .object(entities)])])
        return .object(fields)
    }

    public mutating func apply(patches: [JSONValue], baseRevision: Int, revision: Int) throws {
        guard baseRevision == self.revision, revision > baseRevision else { throw ProtocolFailure.missingSnapshot }
        var next = state
        for patch in patches {
            let path = patch["path"].array
            guard let op = patch["op"].string, ["replace", "add", "remove"].contains(op) else { throw ProtocolFailure.invalidPatch }
            if path.isEmpty {
                guard op == "replace" else { throw ProtocolFailure.invalidPatch }
                next = Self.project(patch["value"]); continue
            }
            guard let first = path.first?.string else { throw ProtocolFailure.invalidPatch }
            var value = patch["value"]
            if Self.scalarKeys.contains(first) { /* Apply metadata patches below. */ }
            else if first == "requests" {
                if path.count == 1 { value = .array(value.array.map { .object($0.object.filter { ["id", "method"].contains($0.key) }) }) }
                else if path.count == 2 { value = .object(value.object.filter { ["id", "method"].contains($0.key) }) }
                else if !["id", "method"].contains(path[2].string ?? "") { continue }
            } else if first == "turns" {
                if path.count == 1 { value = .array(value.array.map(Self.projectTurn)) }
                else if path.count == 2 { value = Self.projectTurn(value) }
                else if !["status", "turnId", "turnStartedAtMs", "error"].contains(path[2].string ?? "") { continue }
            } else if first == "turnHistory" {
                if path.count == 1 { value = Self.project(.object(["turnHistory": value]))["turnHistory"] }
                else if path.count == 2 && path[1].string == "history" {
                    value = Self.project(.object(["turnHistory": .object(["history": value])]))["turnHistory"]["history"]
                } else if path.count >= 3 && path[1].string == "history" && path[2].string == "entitiesByKey" {
                    if path.count == 3 { value = .object(value.object.mapValues(Self.projectTurn)) }
                    else if path.count == 4 { value = Self.projectTurn(value) }
                    else if !["status", "turnId", "turnStartedAtMs", "error"].contains(path[4].string ?? "") { continue }
                } else { continue }
            } else { continue }
            try Self.patch(&next, path: ArraySlice(path), op: op, value: value)
        }
        state = next
        self.revision = revision
    }

    private static func patch(_ node: inout JSONValue, path: ArraySlice<JSONValue>, op: String, value: JSONValue) throws {
        guard let segment = path.first else { node = value; return }
        switch node {
        case .object(var fields):
            guard let key = segment.string else { throw ProtocolFailure.invalidPatch }
            if path.count == 1 {
                if op == "remove" { fields.removeValue(forKey: key) } else { fields[key] = value }
            } else {
                guard var child = fields[key] else { throw ProtocolFailure.invalidPatch }
                try patch(&child, path: path.dropFirst(), op: op, value: value)
                fields[key] = child
            }
            node = .object(fields)
        case .array(var values):
            guard let n = segment.number, n >= 0, n < Double(Int.max), n.rounded() == n else { throw ProtocolFailure.invalidPatch }
            let index = Int(n)
            if path.count == 1 {
                if op == "add", index <= values.count { values.insert(value, at: index) }
                else if op == "remove", index < values.count { values.remove(at: index) }
                else if op == "replace", index < values.count { values[index] = value }
                else { throw ProtocolFailure.invalidPatch }
            } else {
                guard index < values.count else { throw ProtocolFailure.invalidPatch }
                try patch(&values[index], path: path.dropFirst(), op: op, value: value)
            }
            node = .array(values)
        default: throw ProtocolFailure.invalidPatch
        }
    }

    public func summary(id: String, hostID: String) -> ThreadSummary {
        let runtime = state["threadRuntimeStatus"]
        let flags = runtime["activeFlags"].array.compactMap(\.string)
        let methods = state["requests"].array.compactMap { $0["method"].string }
        let turns = state["turns"].array + Array(state["turnHistory"]["history"]["entitiesByKey"].object.values)
        let latest = turns.max { ($0["turnStartedAtMs"].number ?? 0) < ($1["turnStartedAtMs"].number ?? 0) } ?? .null
        let status = runtime["type"].string
        let reviewer = state["currentPermissions"]["approvalsReviewer"].string
        let humanApproval = flags.contains("waitingOnApproval") && (reviewer == nil || reviewer == "user")
        let inputRequest = methods.contains { $0.hasSuffix("/requestUserInput") || $0.hasSuffix("/requestOptionPicker") || $0 == "mcpServer/elicitation/request" || $0 == "item/plan/requestImplementation" }
        let approvalRequest = methods.contains { $0.hasSuffix("/requestApproval") }
        let phase: ThreadPhase
        let detail: String
        if flags.contains("waitingOnUserInput") || inputRequest { phase = .waiting; detail = "Potřebuje odpověď" }
        else if humanApproval || approvalRequest { phase = .waiting; detail = "Potřebuje schválení" }
        else if status == "active" { phase = .running; detail = "Agent pracuje" }
        else if status == "systemError" || latest["status"].string == "failed" { phase = .failed; detail = "Otevři chat pro podrobnosti" }
        else if status == "idle" { phase = .idle; detail = latest["status"].string == "interrupted" ? "Přerušeno" : "Připraveno" }
        else { phase = .unknown; detail = "Chat není načtený" }
        let source = state["source"].string ?? ""
        let subagent = state["threadSource"].string == "subagent" || source.contains("thread_spawn") || state["agentNickname"].string != nil
        let title = state["title"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
        var parent = state["parentThreadId"].string
        if parent == nil, let data = source.data(using: .utf8), let value = try? JSONValue.decode(data) {
            parent = value["subagent"]["thread_spawn"]["parent_thread_id"].string
        }
        return ThreadSummary(id: id, hostID: hostID,
            title: (title?.isEmpty == false ? title : nil) ?? state["agentNickname"].string ?? "Codex chat",
            phase: phase, detail: detail, updatedAt: Date(timeIntervalSince1970: (state["updatedAt"].number ?? 0) / 1000),
            startedAt: latest["turnStartedAtMs"].number.map { Date(timeIntervalSince1970: $0 / 1000) },
            isSubagent: subagent, parentID: parent, turnID: latest["turnId"].string)
    }
}
