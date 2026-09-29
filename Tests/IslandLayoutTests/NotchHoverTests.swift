import XCTest
@testable import CodexIsland

final class NotchHoverTests: XCTestCase {
    func testApproachRequiresContinuousDwell() {
        var state = NotchHoverState()
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 0))
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 0.08))
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 0.16))
        XCTAssertTrue(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 0.18))
    }

    func testBriefTransitDoesNotAccumulateAcrossVisits() {
        var state = NotchHoverState()
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 0))
        XCTAssertFalse(state.sample(insideApproach: false, insideSurface: false, mouseDown: false, now: 0.1))
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 1))
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 1.17))
        XCTAssertTrue(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 1.18))
    }

    func testHiddenSurfaceBoundsCannotRevealTheFoot() {
        var state = NotchHoverState()
        XCTAssertFalse(state.sample(insideApproach: false, insideSurface: true, mouseDown: false, now: 0))
        XCTAssertFalse(state.sample(insideApproach: false, insideSurface: true, mouseDown: false, now: 20))
        XCTAssertFalse(state.sample(insideApproach: false, insideSurface: false, mouseDown: false, now: 40))
    }

    func testMovingFromApproachToVisibleSurfaceKeepsItOpen() {
        var state = visibleState()
        XCTAssertTrue(state.sample(insideApproach: false, insideSurface: true, mouseDown: false, now: 1))
        XCTAssertTrue(state.sample(insideApproach: false, insideSurface: true, mouseDown: false, now: 20))
        XCTAssertTrue(state.sample(insideApproach: false, insideSurface: true, mouseDown: true, now: 21))
    }

    func testExitGraceAllowsCrossingToTheFootWithoutFlicker() {
        var state = visibleState()
        XCTAssertTrue(state.sample(insideApproach: false, insideSurface: false, mouseDown: false, now: 1))
        XCTAssertTrue(state.sample(insideApproach: false, insideSurface: false, mouseDown: false, now: 1.3))
        XCTAssertTrue(state.sample(insideApproach: false, insideSurface: true, mouseDown: false, now: 1.31))
        XCTAssertTrue(state.sample(insideApproach: false, insideSurface: false, mouseDown: false, now: 2))
        XCTAssertTrue(state.sample(insideApproach: false, insideSurface: false, mouseDown: false, now: 2.34))
        XCTAssertFalse(state.sample(insideApproach: false, insideSurface: false, mouseDown: false, now: 2.35))
    }

    func testDraggingRequiresFreshDwellAfterRelease() {
        var state = NotchHoverState()
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: true, now: 0))
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: true, now: 10))
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 11))
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 11.17))
        XCTAssertTrue(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 11.18))
    }

    func testPressingDuringDwellCancelsPendingReveal() {
        var state = NotchHoverState()
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 0))
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: true, now: 0.1))
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 1))
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 1.17))
        XCTAssertTrue(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 1.18))
    }

    func testManualCloseSuppressesUntilBothZonesHaveBeenLeft() {
        var state = visibleState()
        state.suppressUntilExit()
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: true, mouseDown: false, now: 1))
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 2))
        XCTAssertFalse(state.sample(insideApproach: false, insideSurface: true, mouseDown: false, now: 3))
        XCTAssertFalse(state.sample(insideApproach: false, insideSurface: false, mouseDown: false, now: 4))
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 5))
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 5.17))
        XCTAssertTrue(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 5.18))
    }

    func testReturningAfterNormalDismissalRequiresFreshDwell() {
        var state = visibleState()
        XCTAssertTrue(state.sample(insideApproach: false, insideSurface: false, mouseDown: false, now: 1))
        XCTAssertFalse(state.sample(insideApproach: false, insideSurface: false, mouseDown: false, now: 2))
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 3))
        XCTAssertTrue(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 3.18))
    }

    func testReplacingStateClearsVisibilityAndSuppression() {
        var state = visibleState()
        state = NotchHoverState()
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 1))
        state.suppressUntilExit()
        state = NotchHoverState()
        XCTAssertFalse(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 2))
        XCTAssertTrue(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 2.18))
    }

    func testBodyWindowNeverOccupiesMenuBarInAnyPhase() throws {
        for origin in [CGPoint.zero, CGPoint(x: -1470, y: 200)] {
            let geometry = try notchGeometry(origin: origin)
            for capacity in 1...IslandLayout.maximumRows {
                for phase in [NotchPhase.resting, .revealed, .expanded] {
                    let body = geometry.bodyFrame(phase: phase, capacity: capacity)
                    XCTAssertEqual(body.maxY, geometry.frame.minY)
                    XCTAssertEqual(body.midX, geometry.frame.midX)
                    for x in [geometry.frame.minX - 20, geometry.frame.maxX + 20] {
                        let menuPoint = CGPoint(x: x, y: geometry.frame.midY)
                        XCTAssertFalse(geometry.frame.contains(menuPoint))
                        XCTAssertFalse(body.contains(menuPoint))
                    }
                }
            }
        }
    }

    func testBodyResizeKeepsEntireWindowBelowMenuBar() throws {
        let geometry = try notchGeometry()
        let phases: [NotchPhase] = [.resting, .revealed, .expanded]
        for from in phases {
            for to in phases {
                let start = geometry.bodyFrame(phase: from, capacity: 1)
                let end = geometry.bodyFrame(phase: to, capacity: 3)
                for step in 0...100 {
                    let progress = CGFloat(step) / 100
                    let y = start.minY + (end.minY - start.minY) * progress
                    let height = start.height + (end.height - start.height) * progress
                    XCTAssertEqual(y + height, geometry.frame.minY, accuracy: 0.000001)
                }
            }
        }
    }

    func testApproachZoneDoesNotBecomeAnInvisibleRestingWindow() throws {
        let geometry = try notchGeometry()
        let approachPoint = CGPoint(x: geometry.frame.midX, y: geometry.frame.minY - 6)
        XCTAssertTrue(geometry.approachFrame.contains(approachPoint))
        XCTAssertFalse(geometry.frame.contains(approachPoint))
        let restingBody = geometry.bodyFrame(phase: .resting, capacity: 3)
        XCTAssertTrue(restingBody.isEmpty)
        XCTAssertFalse(restingBody.contains(approachPoint))
        XCTAssertTrue(geometry.bodyFrame(phase: .revealed, capacity: 3).contains(approachPoint))
    }

    private func notchGeometry(origin: CGPoint = .zero) throws -> NotchGeometry {
        try XCTUnwrap(NotchGeometry(
            screen: CGRect(x: origin.x, y: origin.y, width: 1470, height: 956),
            visible: CGRect(x: origin.x, y: origin.y, width: 1470, height: 922),
            safeTop: 32,
            left: CGRect(x: origin.x, y: origin.y + 924, width: 646, height: 32),
            right: CGRect(x: origin.x + 825, y: origin.y + 924, width: 645, height: 32),
            scale: 2))
    }

    private func visibleState() -> NotchHoverState {
        var state = NotchHoverState()
        _ = state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 0)
        XCTAssertTrue(state.sample(insideApproach: true, insideSurface: false, mouseDown: false, now: 0.18))
        return state
    }
}
