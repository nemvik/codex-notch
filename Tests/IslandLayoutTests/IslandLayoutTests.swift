import XCTest
import IslandCore
@testable import CodexIsland

final class IslandLayoutTests: XCTestCase {
    private func geometry(visibleTop: CGFloat = 922, safeTop: CGFloat = 32) -> NotchGeometry? {
        NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                      visible: CGRect(x: 0, y: 0, width: 1470, height: visibleTop), safeTop: safeTop,
                      left: CGRect(x: 0, y: 924, width: 646, height: 32),
                      right: CGRect(x: 825, y: 924, width: 645, height: 32), scale: 2)
    }
    func testIndicatorUsesOnlyDrawableMenuBarBandAndCameraColumn() throws {
        let g = try XCTUnwrap(geometry())
        XCTAssertEqual(g.frame, CGRect(x: 646, y: 922, width: 179, height: 34))
        XCTAssertEqual(g.bandHeight, 2)
        XCTAssertEqual(g.lineHeight, 1.5)
        let lineBottom = g.frame.minY + (g.bandHeight - g.lineHeight) / 2
        XCTAssertGreaterThanOrEqual(lineBottom, 922)
        XCTAssertLessThanOrEqual(lineBottom + g.lineHeight, 924)
        XCTAssertLessThan(g.lineWidth, g.frame.width)
    }
    func testNeverInventsSpaceBelowBarOrWithoutNotch() {
        XCTAssertNil(geometry(visibleTop: 924))
        XCTAssertNil(geometry(visibleTop: 956))
        XCTAssertNil(geometry(safeTop: 0))
    }
    func testRejectsInvalidExclusionAndUnexpectedLargeGap() {
        XCTAssertNil(geometry(visibleTop: 900))
        XCTAssertNil(NotchGeometry(screen: .zero, visible: .zero, safeTop: 32, left: nil, right: nil, scale: 2))
    }
    func testDisconnectedDoesNotImplyIdleEvenWithHistoricalResults() {
        var store = ActivityStore()
        store.update([ThreadSummary(id: "a", title: "Fixture", phase: .running)])
        let state = IslandIndicator(activity: store, connected: false)
        XCTAssertEqual(state.title, "")
        XCTAssertEqual(state.symbol, "link.badge.plus")
    }
    func testHumanAttentionTakesPriorityOverRunningCount() {
        var store = ActivityStore()
        store.update([ThreadSummary(id: "a", title: "Fixture", phase: .running), ThreadSummary(id: "b", title: "Fixture", phase: .running), ThreadSummary(id: "c", title: "Fixture", phase: .waiting)])
        let state = IslandIndicator(activity: store, connected: true)
        XCTAssertEqual(state.title, "1")
        XCTAssertEqual(state.symbol, "exclamationmark.bubble")
    }
    func testCompletionIsShownUntilAcknowledged() {
        var store = ActivityStore()
        store.update([ThreadSummary(id: "a", title: "Fixture", phase: .running)])
        store.update([ThreadSummary(id: "a", title: "Fixture", phase: .idle)])
        XCTAssertEqual(IslandIndicator(activity: store, connected: true).symbol, "checkmark.circle")
        store.acknowledge()
        XCTAssertEqual(IslandIndicator(activity: store, connected: true).symbol, "moon")
    }
    func testLargeCountsKeepFallbackMenuItemCompactWithoutLosingActualCount() {
        var store = ActivityStore()
        store.update((0..<120).map { ThreadSummary(id: String($0), title: "Fixture", phase: .running) })
        XCTAssertEqual(IslandIndicator(activity: store, connected: true).title, "99+")
        XCTAssertEqual(store.runningTasks, 120)
    }
}
