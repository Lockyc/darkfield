import CoreGraphics
import DarkfieldCore
import XCTest

final class ParkingTests: XCTestCase {
    let size = CGSize(width: 1920, height: 1080)

    func testOnePointOnTheOnlyDisplay() {
        let d = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(Parking.frame(size: size, displays: [d]), CGRect(x: 1511, y: 981, width: 1920, height: 1080))
    }

    func testSkipsACornerAnotherDisplayWouldShow() {
        // An external to the right of the laptop, lower than it: the laptop's corner would put
        // the window over the external, so the external's corner is used.
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let external = CGRect(x: 1512, y: 200, width: 2560, height: 1440)
        XCTAssertEqual(Parking.frame(size: size, displays: [laptop, external]),
                       CGRect(x: 4071, y: 1639, width: 1920, height: 1080))
    }

    func testWhollyOffScreenWhenNoCornerIsClear() {
        // Two displays at the same bounds: every corner point is on both.
        let a = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let frame = Parking.frame(size: size, displays: [a, a])
        XCTAssertFalse(a.intersects(frame))
    }
}

final class PickingTests: XCTestCase {
    func testCentredOnTheDisplaySoAClickCanReachIt() {
        let tv = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        XCTAssertEqual(Parking.pickingFrame(size: CGSize(width: 1920, height: 1080), display: tv),
                       CGRect(x: 960, y: 540, width: 1920, height: 1080))
    }

    func testCentredOnADisplayAwayFromTheOrigin() {
        let laptop = CGRect(x: -2056, y: 0, width: 2056, height: 1329)
        let r = Parking.pickingFrame(size: CGSize(width: 1920, height: 1080), display: laptop)
        XCTAssertEqual(r.midX, laptop.midX)
        XCTAssertEqual(r.midY, laptop.midY)
    }
}
