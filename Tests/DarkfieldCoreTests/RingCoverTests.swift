import XCTest
import CoreGraphics
@testable import DarkfieldCore

final class RingCoverTests: XCTestCase {
    private let ring = CGRect(x: 96, y: 96, width: 208, height: 108) // shared window 100,100 200x100, ring 4 out

    private func w(_ id: CGWindowID, _ x: CGFloat, _ y: CGFloat, _ wd: CGFloat, _ h: CGFloat) -> OnScreenWindow {
        OnScreenWindow(id: id, frame: CGRect(x: x, y: y, width: wd, height: h))
    }

    func testNothingInFrontCoversNothing() {
        let stack = [w(1, 100, 100, 200, 100), w(2, 150, 150, 300, 300)]
        XCTAssertEqual(RingCover.covers(ring: ring, shared: 1, stack: stack), [])
    }

    func testWindowInFrontIsCutOutInRingLocalYUpPoints() {
        // Window 2 is in front and covers the shared window's bottom-right quarter (CG y down).
        let stack = [w(2, 200, 150, 300, 300), w(1, 100, 100, 200, 100)]
        // Ring-local, y up: x 200-96 = 104; CG bottom edge of ring is 204, cover's top is 150 →
        // local y from 0 to 204-150 = 54; clipped to the ring.
        XCTAssertEqual(RingCover.covers(ring: ring, shared: 1, stack: stack), [CGRect(x: 104, y: 0, width: 104, height: 54)])
    }

    func testIgnoredWindowsAndOnesNotOverlappingAreSkipped() {
        let stack = [w(9, 0, 0, 1000, 1000), w(3, 600, 600, 50, 50), w(1, 100, 100, 200, 100)]
        XCTAssertEqual(RingCover.covers(ring: ring, shared: 1, stack: stack, ignoring: [9]), [])
    }

    func testOnlyVisibleWindowsAtOrBelowTheRingsLevelCanCoverIt() {
        let floating = Int(CGWindowLevelForKey(.floatingWindow))
        XCTAssertTrue(RingCover.canCover(layer: 0, alpha: 1))
        XCTAssertTrue(RingCover.canCover(layer: floating, alpha: 1))
        XCTAssertFalse(RingCover.canCover(layer: 0, alpha: 0))
        // Notification Centre's full-display banner host (layer 23) and the menu bar already draw
        // over the ring; cutting for them blanks the whole ring while a banner shows.
        XCTAssertFalse(RingCover.canCover(layer: 23, alpha: 1))
        XCTAssertFalse(RingCover.canCover(layer: Int(CGWindowLevelForKey(.mainMenuWindow)), alpha: 1))
    }

    func testSharedWindowAbsentCoversNothing() {
        XCTAssertEqual(RingCover.covers(ring: ring, shared: 1, stack: [w(2, 0, 0, 500, 500)]), [])
    }
}
