import Foundation
import Network
import Darwin

public enum FeedConnection: String, Sendable { case connecting, connected, disconnected, incompatible }
public enum FeedEvent: Sendable {
    case connection(FeedConnection, String)
    case summaries([ThreadSummary])
    case catalogCount(Int)
}

/// All mutable protocol state is confined to queue. This client never claims thread ownership,
/// answers approval prompts, starts work, or writes to any Codex database.
public final class DesktopFeed: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.nemvik.codex-island.feed", qos: .utility)
    private let home: URL
    private let handler: @Sendable (FeedEvent) -> Void
    private var connection: NWConnection?
    private var decoder = FrameDecoder()
    private var clientID: String?
    private var projections: [String: ThreadProjection] = [:]
    private var summaries: [String: ThreadSummary] = [:]
    private var owners: [String: String] = [:]
    private var subscriptions: Set<String> = []
    private var catalogIDs: Set<String> = []
    private var catalogSubagents: Set<String> = []
    private var pendingSnapshots: Set<String> = []
    private var timer: DispatchSourceTimer?
    private var publishItem: DispatchWorkItem?
    private var reconnectItem: DispatchWorkItem?
    private var running = false
    private var generation = 0
    private var reconnectDelay: Double = 2
    private var catalogFailed = false

    public init(home: URL, handler: @escaping @Sendable (FeedEvent) -> Void) {
        self.home = home; self.handler = handler
    }

    public func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 15, repeating: 15, leeway: .seconds(2))
            timer.setEventHandler { [weak self] in self?.discoverThreads() }
            self.timer = timer; timer.resume()
            connect()
        }
    }

    public func stop() {
        queue.async { [self] in
            running = false; generation += 1
            timer?.cancel(); timer = nil
            reconnectItem?.cancel(); publishItem?.cancel()
            connection?.cancel(); connection = nil
            clientID = nil; projections.removeAll(); summaries.removeAll(); subscriptions.removeAll()
        }
    }

    public func reconnect() {
        queue.async { [self] in
            guard running else { return }
            reconnectDelay = 2; reconnectItem?.cancel()
            connect()
        }
    }

    private func connect() {
        guard running else { return }
        generation += 1
        connection?.cancel(); connection = nil
        clientID = nil; decoder = FrameDecoder()
        projections.removeAll(); summaries.removeAll(); owners.removeAll(); subscriptions.removeAll()
        pendingSnapshots.removeAll()
        handler(.summaries([]))
        handler(.connection(.connecting, "Připojuji se ke Codexu…"))
        let path = home.appendingPathComponent("ipc/ipc.sock").path
        do { try Self.validateSocket(path) }
        catch { fail(error.localizedDescription); return }
        let current = generation
        let socket = NWConnection(to: .unix(path: path), using: .tcp)
        connection = socket
        socket.stateUpdateHandler = { [weak self, weak socket] state in
            guard let self, let socket, self.generation == current else { return }
            switch state {
            case .ready:
                self.send(.object(["type": .string("request"), "requestId": .string("island-initialize"),
                    "method": .string("initialize"), "version": .number(0),
                    "params": .object(["clientType": .string("codex-island")])]))
                self.receive(socket, generation: current)
                self.queue.asyncAfter(deadline: .now() + 6) { [weak self] in
                    guard let self, self.generation == current, self.clientID == nil else { return }
                    self.fail("Codex neodpovídá. Zkus ho znovu spustit.")
                }
            case .failed(let error): self.fail("Codex je odpojený: \(error.localizedDescription)")
            case .waiting(let error): self.fail("Codex není dostupný: \(error.localizedDescription)")
            default: break
            }
        }
        socket.start(queue: queue)
    }

    private static func validateSocket(_ path: String) throws {
        for (candidate, isSocket) in [(URL(fileURLWithPath: path).deletingLastPathComponent().path, false), (path, true)] {
            var info = stat()
            guard lstat(candidate, &info) == 0 else {
                throw NSError(domain: "CodexIsland", code: 1, userInfo: [NSLocalizedDescriptionKey: "Codex neběží. Spusť desktopovou aplikaci Codex."])
            }
            let expected = isSocket ? S_IFSOCK : S_IFDIR
            guard info.st_uid == getuid(), (info.st_mode & S_IFMT) == expected,
                  (info.st_mode & (isSocket ? 0o077 : 0o022)) == 0 else {
                throw NSError(domain: "CodexIsland", code: 2, userInfo: [NSLocalizedDescriptionKey: "Socket Codexu nemá bezpečné vlastnictví nebo oprávnění."])
            }
        }
    }

    private func receive(_ socket: NWConnection, generation current: Int) {
        socket.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak socket] data, _, complete, error in
            guard let self, let socket, self.generation == current else { return }
            do {
                if let data {
                    for message in try self.decoder.append(data) { try self.handle(message) }
                }
            } catch {
                self.fail(error.localizedDescription, incompatible: error is ProtocolFailure); return
            }
            if complete || error != nil { self.fail("Codex je odpojený."); return }
            self.receive(socket, generation: current)
        }
    }

    private func send(_ message: JSONValue) {
        guard let connection else { return }
        do {
            let current = generation
            connection.send(content: try FrameDecoder.encode(message), completion: .contentProcessed { [weak self] error in
                guard let self, self.generation == current else { return }
                if let error { self.fail(error.localizedDescription) }
            })
        } catch { fail(error.localizedDescription, incompatible: true) }
    }

    private func handle(_ message: JSONValue) throws {
        switch message["type"].string {
        case "response":
            if message["requestId"].string == "island-initialize" {
                guard message["resultType"].string == "success", let id = message["result"]["clientId"].string else {
                    throw ProtocolFailure.incompatibleVersion
                }
                clientID = id; reconnectDelay = 2
                discoverThreads()
                if !catalogFailed { handler(.connection(.connected, "Živě · místní Codex")) }
            }
        case "client-discovery-request":
            send(.object(["type": .string("client-discovery-response"), "requestId": message["requestId"],
                          "response": .object(["canHandle": .bool(false)])]))
        case "request":
            send(.object(["type": .string("response"), "requestId": message["requestId"],
                          "resultType": .string("error"), "error": .string("observer-only")]))
        case "broadcast":
            guard let method = message["method"].string else { return }
            let params = message["params"]
            if case .array(let targets) = message["targetClientIds"], !targets.contains(.string(clientID ?? "")) { return }
            switch method {
            case "thread-stream-state-changed":
                guard message["version"].number == 11 else { throw ProtocolFailure.incompatibleVersion }
                guard params["hostId"].string == "local", let id = params["conversationId"].string,
                      catalogIDs.contains(id) else { return }
                let key = "local:" + id
                let change = params["change"]
                guard let revisionValue = change["revision"].number, revisionValue >= 0,
                      revisionValue < Double(Int.max), revisionValue.rounded() == revisionValue else { throw ProtocolFailure.malformedFrame }
                let revision = Int(revisionValue)
                if change["type"].string == "snapshot" {
                    projections[key] = ThreadProjection(snapshot: change["conversationState"], revision: revision)
                    owners[key] = message["sourceClientId"].string
                    if pendingSnapshots.remove(id) != nil, pendingSnapshots.isEmpty, !catalogFailed {
                        handler(.connection(.connected, "Živě · místní Codex"))
                    }
                } else if change["type"].string == "patches" {
                    guard let base = change["baseRevision"].number, base >= 0, base < Double(Int.max), base.rounded() == base else {
                        throw ProtocolFailure.malformedFrame
                    }
                    guard var projection = projections[key], owners[key] == message["sourceClientId"].string else {
                        requestSnapshot(id); return
                    }
                    if revision <= projection.revision { return } // An in-flight old patch may follow a fresh snapshot.
                    do { try projection.apply(patches: change["patches"].array, baseRevision: Int(base), revision: revision) }
                    catch ProtocolFailure.missingSnapshot {
                        projections.removeValue(forKey: key); summaries.removeValue(forKey: key)
                        publishSoon(); requestSnapshot(id); return
                    }
                    projections[key] = projection
                } else { throw ProtocolFailure.incompatibleVersion }
                guard projections[key]?.isCompatible == true else { throw ProtocolFailure.incompatibleVersion }
                if var summary = projections[key]?.summary(id: id, hostID: "local") {
                    if catalogSubagents.contains(id) { summary.isSubagent = true }
                    if summaries[key] != summary { summaries[key] = summary; publishSoon() }
                }
            case "thread-stream-following-changed", "thread-stream-following-status-requested":
                guard params["hostId"].string == "local", let id = params["conversationId"].string,
                      message["sourceClientId"].string != clientID else { return }
                if !catalogIDs.contains(id) { discoverThreads() }
                if catalogIDs.contains(id) { follow(id) }
            case "client-status-changed":
                if params["status"].string == "disconnected", let id = params["clientId"].string {
                    let gone = owners.filter { $0.value == id }.map(\.key)
                    for key in gone {
                        projections.removeValue(forKey: key); summaries.removeValue(forKey: key); owners.removeValue(forKey: key)
                        subscriptions.remove(String(key.dropFirst(6)))
                    }
                    publishSoon()
                } else if params["status"].string == "connected" { discoverThreads(force: true) }
            case "thread-archived":
                if params["hostId"].string == "local" { discoverThreads() }
            default: break
            }
        default: break
        }
    }

    private func follow(_ id: String, force: Bool = false, following: Bool = true) {
        guard let clientID, force || !subscriptions.contains(id) else { return }
        if following { subscriptions.insert(id) } else { subscriptions.remove(id) }
        send(.object(["type": .string("broadcast"), "method": .string("thread-stream-following-changed"),
            "version": .number(1), "sourceClientId": .string(clientID),
            "params": .object(["hostId": .string("local"), "conversationId": .string(id), "following": .bool(following)])]))
    }

    private func requestSnapshot(_ id: String) {
        guard pendingSnapshots.insert(id).inserted else { return }
        handler(.connection(.connecting, "Obnovuji živý stav chatu…"))
        follow(id, force: true)
        let current = generation
        queue.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.generation == current, self.pendingSnapshots.contains(id) else { return }
            self.fail("Codex neobnovil živý stav. Připojuji se znovu.")
        }
    }

    private func discoverThreads(force: Bool = false) {
        guard clientID != nil else { return }
        do {
            let entries = try ThreadCatalog(home: home).entries()
            let current = Set(entries.map(\.id))
            let removed = catalogIDs.subtracting(current)
            let wasRecovering = !pendingSnapshots.isEmpty
            catalogIDs = current
            catalogSubagents = Set(entries.filter(\.isSubagent).map(\.id))
            handler(.catalogCount(entries.count))
            for id in removed {
                follow(id, force: true, following: false)
                projections.removeValue(forKey: "local:" + id); summaries.removeValue(forKey: "local:" + id)
                owners.removeValue(forKey: "local:" + id)
                pendingSnapshots.remove(id)
            }
            if !removed.isEmpty { publishSoon() }
            if wasRecovering && pendingSnapshots.isEmpty && !catalogFailed {
                handler(.connection(.connected, "Živě · místní Codex"))
            }
            for entry in entries { follow(entry.id, force: force) }
            if catalogFailed && pendingSnapshots.isEmpty {
                handler(.connection(.connected, "Živě · místní Codex"))
                handler(.summaries(Array(summaries.values)))
            }
            catalogFailed = false
        } catch {
            catalogFailed = true
            handler(.connection(.disconnected, error.localizedDescription))
        }
    }

    private func publishSoon() {
        guard publishItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.publishItem = nil
            self.handler(.summaries(Array(self.summaries.values)))
        }
        publishItem = item; queue.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private func fail(_ reason: String, incompatible: Bool = false) {
        guard running else { return }
        generation += 1
        connection?.cancel(); connection = nil; clientID = nil
        publishItem?.cancel(); publishItem = nil
        handler(.connection(incompatible ? .incompatible : .disconnected, reason))
        handler(.summaries([]))
        reconnectItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.connect() }
        reconnectItem = item
        queue.asyncAfter(deadline: .now() + (incompatible ? 30 : reconnectDelay), execute: item)
        reconnectDelay = min(15, reconnectDelay * 2)
    }
}
