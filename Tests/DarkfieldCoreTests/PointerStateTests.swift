import XCTest
import CoreGraphics
@testable import DarkfieldCore

final class PointerStateTests: XCTestCase {
    func testOpacityFullThenFades() {
        var p = PointerState()
        p.moved(to: .zero, at: 0)
        XCTAssertEqual(p.opacity(at: 9.9, idleFade: 10), 1, accuracy: 0.0001)
        XCTAssertEqual(p.opacity(at: 10.25, idleFade: 10), 0.5, accuracy: 0.0001)
        XCTAssertEqual(p.opacity(at: 11, idleFade: 10), 0, accuracy: 0.0001)
    }

    func testNeverFades() {
        var p = PointerState()
        p.moved(to: .zero, at: 0)
        XCTAssertEqual(p.opacity(at: 1000, idleFade: nil), 1)
    }

    func testMoveRestores() {
        var p = PointerState()
        p.moved(to: .zero, at: 0)
        XCTAssertEqual(p.opacity(at: 20, idleFade: 10), 0)
        p.moved(to: CGPoint(x: 5, y: 0), at: 20)
        XCTAssertEqual(p.opacity(at: 20, idleFade: 10), 1)
    }

    func testShakeEnlarges() {
        var p = PointerState()
        for (i, x) in [0.0, 40, 0, 40, 0, 40].enumerated() {
            p.moved(to: CGPoint(x: x, y: 0), at: Double(i) * 0.1)
        }
        XCTAssertEqual(p.spotlightScale(at: 0.55), 3.0)
        XCTAssertEqual(p.spotlightScale(at: 0.5 + 0.81), 1.0)
    }

    func testSlowWiggleIsNotShake() {
        var p = PointerState()
        for (i, x) in [0.0, 40, 0, 40, 0, 40].enumerated() {
            p.moved(to: CGPoint(x: x, y: 0), at: Double(i) * 0.4)
        }
        XCTAssertEqual(p.spotlightScale(at: 2.05), 1.0)
    }

    func testSmallJitterIsNotShake() {
        var p = PointerState()
        for (i, x) in [0.0, 10, 0, 10, 0, 10, 0].enumerated() {
            p.moved(to: CGPoint(x: x, y: 0), at: Double(i) * 0.05)
        }
        XCTAssertEqual(p.spotlightScale(at: 0.35), 1.0)
    }

    func testRadius() {
        XCTAssertEqual(PointerState.radius(canvasHeight: 1080), 19.44, accuracy: 0.001)
    }

    func testRippleDuration() {
        XCTAssertEqual(Ripple.duration, 0.4)
        let r = Ripple(at: .zero, kind: .right, start: 3)
        XCTAssertEqual(r.kind, .right)
    }
}
