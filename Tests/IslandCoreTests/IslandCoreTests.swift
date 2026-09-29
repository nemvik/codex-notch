import XCTest
import Foundation
import CSQLite
@testable import IslandCore

final class FrameTests: XCTestCase {
    func testSplitFramesAndCoalescedFramesWithUnicode() throws {
        let one: JSONValue = .object(["title": .string("Čeká na tebe ✨")])
        let two: JSONValue = .array([.number(4), .bool(true), .null])
        let first = try FrameDecoder.encode(one)
        let second = try FrameDecoder.encode(two)
        var decoder = FrameDecoder()
        XCTAssertEqual(try decoder.append(first.prefix(2)), [])
        XCTAssertEqual(try decoder.append(first.dropFirst(2).prefix(5)), [])
        XCTAssertEqual(try decoder.append(first.dropFirst(7) + second), [one, two])
        XCTAssertEqual(try decoder.append(try FrameDecoder.encode(two)), [two])
    }
    func testRejectsOversizedAndEmptyFrames() {
        var decoder = FrameDecoder()
        XCTAssertThrowsError(try decoder.append(Data([255, 255, 255, 255])))
        decoder = FrameDecoder()
        XCTAssertThrowsError(try decoder.append(Data([0, 0, 0, 0])))
    }
    func testRejectsMalformedJSON() {
        var decoder = FrameDecoder()
        XCTAssertThrowsError(try decoder.append(Data([1, 0, 0, 0, 123])))
    }
}

final class ProjectionTests: XCTestCase {
    private func snapshot(status: String = "active", flags: [String] = [], reviewer: String = "user", turnStatus: String = "inProgress") -> JSONValue {
        .object([
            "id": .string("test"), "title": .string("Úprava aplikace"), "updatedAt": .number(1_790_716_408_000),
            "threadRuntimeStatus": .object(["type": .string(status), "activeFlags": .array(flags.map(JSONValue.string))]),
            "currentPermissions": .object(["approvalsReviewer": .string(reviewer)]),
            "requests": .array([]), "turns": .array([]),
            "turnHistory": .object(["history": .object(["entitiesByKey": .object([
                "turn-old": .object(["status": .string("completed"), "turnStartedAtMs": .number(1000), "turnId": .string("old")]),
                "turn-current": .object(["status": .string(turnStatus), "turnStartedAtMs": .number(2000), "turnId": .string("new"),
                                        "items": .array([.object(["text": .string("private content")])])])
            ])])])
        ])
    }
    private func patch(_ path: [JSONValue], value: JSONValue, op: String = "replace") -> JSONValue {
        .object(["op": .string(op), "path": .array(path), "value": value])
    }
    private func summary(_ projection: ThreadProjection) -> ThreadSummary { projection.summary(id: "test", hostID: "local") }

    func testRuntimeAndLatestCanonicalTurn() {
        let result = summary(ThreadProjection(snapshot: snapshot(), revision: 0))
        XCTAssertEqual(result.phase, .running)
        XCTAssertEqual(result.turnID, "new")
        XCTAssertEqual(result.startedAt, Date(timeIntervalSince1970: 2))
    }
    func testHumanApprovalAndUserInput() {
        XCTAssertEqual(summary(ThreadProjection(snapshot: snapshot(flags: ["waitingOnApproval"]), revision: 0)).phase, .waiting)
        XCTAssertEqual(summary(ThreadProjection(snapshot: snapshot(flags: ["waitingOnUserInput"], reviewer: "guardian_subagent"), revision: 0)).phase, .waiting)
    }
    func testAutomaticApprovalKeepsRunning() {
        XCTAssertEqual(summary(ThreadProjection(snapshot: snapshot(flags: ["waitingOnApproval"], reviewer: "guardian_subagent"), revision: 0)).phase, .running)
    }
    func testPendingQuestionsOverrideIdle() throws {
        for method in ["item/tool/requestUserInput", "item/tool/requestOptionPicker", "item/plan/requestImplementation", "item/permissions/requestApproval"] {
            var projection = ThreadProjection(snapshot: snapshot(status: "idle"), revision: 0)
            try projection.apply(patches: [patch([.string("requests"), .number(0)], value: .object(["id": .string("req"), "method": .string(method)]), op: "add")], baseRevision: 0, revision: 1)
            XCTAssertEqual(summary(projection).phase, .waiting, method)
            try projection.apply(patches: [patch([.string("requests"), .number(0)], value: .null, op: "remove")], baseRevision: 1, revision: 2)
            XCTAssertEqual(summary(projection).phase, .idle)
        }
    }
    func testStatusAndCanonicalFailurePatches() throws {
        var projection = ThreadProjection(snapshot: snapshot(), revision: 10)
        try projection.apply(patches: [
            patch([.string("threadRuntimeStatus"), .string("type")], value: .string("idle")),
            patch([.string("turnHistory"), .string("history"), .string("entitiesByKey"), .string("turn-current"), .string("status")], value: .string("failed"))
        ], baseRevision: 10, revision: 12)
        XCTAssertEqual(summary(projection).phase, .failed)
    }
    func testRevisionGapRequiresNewSnapshotAndLeavesStateUntouched() {
        var projection = ThreadProjection(snapshot: snapshot(), revision: 10)
        XCTAssertThrowsError(try projection.apply(patches: [], baseRevision: 8, revision: 12))
        XCTAssertEqual(projection.revision, 10)
        XCTAssertEqual(summary(projection).phase, .running)
    }
    func testDiscardedToolContentDoesNotBreakPatchStream() throws {
        var projection = ThreadProjection(snapshot: snapshot(), revision: 0)
        try projection.apply(patches: [patch([.string("turnHistory"), .string("history"), .string("entitiesByKey"), .string("turn-current"), .string("items"), .number(0), .string("text")], value: .string("more private content"))], baseRevision: 0, revision: 1)
        XCTAssertEqual(summary(projection).phase, .running)
        XCTAssertEqual(projection.revision, 1)
    }
    func testWholeHistoryReplacementAndTurnInsertion() throws {
        var projection = ThreadProjection(snapshot: snapshot(), revision: 0)
        try projection.apply(patches: [patch([.string("turnHistory")], value: snapshot(turnStatus: "failed")["turnHistory"])], baseRevision: 0, revision: 1)
        try projection.apply(patches: [patch([.string("threadRuntimeStatus")], value: .object(["type": .string("idle")]))], baseRevision: 1, revision: 2)
        XCTAssertEqual(summary(projection).phase, .failed)
    }
    func testInvalidPatchFailsAtomically() throws {
        var projection = ThreadProjection(snapshot: snapshot(), revision: 0)
        XCTAssertThrowsError(try projection.apply(patches: [
            patch([.string("threadRuntimeStatus"), .string("type")], value: .string("idle")),
            patch([.string("requests"), .number(900)], value: .null, op: "remove")
        ], baseRevision: 0, revision: 1))
        XCTAssertEqual(summary(projection).phase, .running)
        XCTAssertEqual(projection.revision, 0)
    }
    func testOlderUnloadedThreadIsUnknownRatherThanIdle() {
        XCTAssertEqual(summary(ThreadProjection(snapshot: snapshot(status: "notLoaded"), revision: 0)).phase, .unknown)
    }
    func testUnknownRuntimeSchemaIsIncompatible() {
        XCTAssertFalse(ThreadProjection(snapshot: snapshot(status: "newUnsupportedStatus"), revision: 0).isCompatible)
        XCTAssertFalse(ThreadProjection(snapshot: .object([:]), revision: 0).isCompatible)
        XCTAssertTrue(ThreadProjection(snapshot: snapshot(status: "notLoaded"), revision: 0).isCompatible)
    }
    func testInterruptedTurnHasDistinctDetail() {
        XCTAssertEqual(summary(ThreadProjection(snapshot: snapshot(status: "idle", turnStatus: "interrupted"), revision: 0)).detail, "Přerušeno")
    }
    func testSubagentParentMetadata() throws {
        var fields = snapshot().object
        fields["source"] = .string("{\"subagent\":{\"thread_spawn\":{\"parent_thread_id\":\"parent\"}}}")
        let result = summary(ThreadProjection(snapshot: .object(fields), revision: 0))
        XCTAssertTrue(result.isSubagent); XCTAssertEqual(result.parentID, "parent")
    }
}

final class ActivityTests: XCTestCase {
    private func row(_ phase: ThreadPhase, id: String = "task", subagent: Bool = false, detail: String = "", turnID: String = "turn") -> ThreadSummary {
        ThreadSummary(id: id, title: id, phase: phase, detail: detail, isSubagent: subagent, turnID: turnID)
    }
    func testSeparateTasksFromSubagentsAndPrioritizeHumanAttention() {
        var store = ActivityStore()
        store.update([row(.running), row(.running, id: "child", subagent: true), row(.waiting, id: "approval")])
        XCTAssertEqual(store.runningTasks, 1); XCTAssertEqual(store.runningSubagents, 1)
        XCTAssertEqual(store.waitingCount, 1); XCTAssertEqual(store.visible.first?.phase, .waiting)
    }
    func testInitialHistoryDoesNotProduceCompletions() {
        var store = ActivityStore(); store.update([row(.idle), row(.failed, id: "old")])
        XCTAssertEqual(store.completionCount, 0); XCTAssertEqual(store.failureCount, 0)
    }
    func testCompletionAcknowledgementAndExpiration() {
        var store = ActivityStore(); let now = Date()
        store.update([row(.running)], now: now); store.update([row(.idle)], now: now)
        XCTAssertEqual(store.completionCount, 1); XCTAssertEqual(store.visible.first?.phase, .completed)
        store.acknowledge(); XCTAssertEqual(store.completionCount, 0)
        store.expire(now: now.addingTimeInterval(601)); XCTAssertTrue(store.finished.isEmpty)
    }
    func testDisconnectAndDisappearanceAreNotSuccess() {
        var store = ActivityStore(); store.update([row(.running)])
        store.disconnect(); store.update([row(.idle)])
        XCTAssertEqual(store.completionCount, 0)
        store.update([row(.running)]); store.update([])
        XCTAssertEqual(store.completionCount, 0)
    }
    func testInterruptedTurnDoesNotProduceSuccess() {
        var store = ActivityStore(); store.update([row(.running)])
        store.update([row(.idle, detail: "Přerušeno")]); XCTAssertEqual(store.completionCount, 0)
    }
    func testFailureAndNewRunClearPreviousResult() {
        var store = ActivityStore(); store.update([row(.running)]); store.update([row(.failed)])
        XCTAssertEqual(store.failureCount, 1)
        store.update([row(.running, turnID: "next")]); XCTAssertEqual(store.failureCount, 0)
    }
    func testDifferentTurnCannotBeCountedAsObservedCompletion() {
        var store = ActivityStore(); store.update([row(.running)])
        store.update([row(.idle, turnID: "other")]); XCTAssertEqual(store.completionCount, 0)
    }
    func testReconnectedNewRunClearsOldUnreadCompletion() {
        var store = ActivityStore(); store.update([row(.running)]); store.update([row(.idle)])
        XCTAssertEqual(store.completionCount, 1)
        store.disconnect(); store.update([row(.running, turnID: "next")])
        XCTAssertEqual(store.completionCount, 0); XCTAssertTrue(store.finished.isEmpty)
    }
}

final class CatalogTests: XCTestCase {
    func testReadonlyDiscoveryChoosesNewestDatabaseAndExcludesGuardiansAndArchives() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("state_12.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE threads (id TEXT, source TEXT, archived INTEGER, updated_at INTEGER);
        INSERT INTO threads VALUES ('active', 'vscode', 0, 5), ('archived', 'vscode', 1, 8),
        ('guardian', '{"subagent":{"other":"guardian"}}', 0, 9),
        ('child', '{"subagent":{"thread_spawn":{}}}', 0, 6);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        try Data().write(to: directory.appendingPathComponent("state_2.sqlite"))
        let entries = try ThreadCatalog(home: directory).entries()
        XCTAssertEqual(entries.map(\.id), ["child", "active"])
        XCTAssertTrue(entries[0].isSubagent)
        let modified = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("state_12.sqlite").path)[.modificationDate] as? Date
        _ = try ThreadCatalog(home: directory).entries()
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("state_12.sqlite").path)[.modificationDate] as? Date, modified)
    }
}
