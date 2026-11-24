import CoreGraphics
import XCTest
@testable import DarkfieldCore

final class FramingTests: XCTestCase {
    private let wide: CGFloat = 16.0 / 9.0
    private let centred = CGRect(x: 0.45, y: 0.3, width: 0.1, height: 0.15)

    private func run(_ f: inout Framing, _ subject: CGRect?, seconds: Double, tightness: Double = 0.5,
                     aspect: CGFloat = 16.0 / 9.0) {
        for _ in 0..<Int(seconds * 30) { f.step(subject: subject, tightness: tightness, sourceAspect: aspect, dt: 1.0 / 30) }
    }

    func testStartsFullFrame() {
        XCTAssertEqual(Framing().crop, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testCentredSubjectConverges() {
        var f = Framing()
        run(&f, centred, seconds: 8)
        XCTAssertEqual(f.crop.midX, 0.5, accuracy: 0.01)
        // At the default tightness the face is a sixth of the frame's width, like Google Meet's framing.
        XCTAssertEqual(f.crop.width, 0.6, accuracy: 0.02)
    }

    func testFaceSitsMidFrameLeavingHeadroom() {
        var f = Framing()
        run(&f, centred, seconds: 8)
        XCTAssertEqual((centred.midY - f.crop.minY) / f.crop.height, 0.5, accuracy: 0.02)
    }

    func testCropStaysInsideAtEdge() {
        var f = Framing()
        run(&f, CGRect(x: 0, y: 0.3, width: 0.1, height: 0.15), seconds: 8)
        XCTAssertGreaterThanOrEqual(f.crop.minX, 0)
        XCTAssertLessThanOrEqual(f.crop.maxX, 1)
        XCTAssertGreaterThanOrEqual(f.crop.minY, 0)
        XCTAssertLessThanOrEqual(f.crop.maxY, 1)
    }

    func testDeadZoneHoldsSmallMoves() {
        var f = Framing()
        run(&f, centred, seconds: 12)
        let settled = f.crop
        // Half a face-width sideways, held: a shift in the seat.
        run(&f, centred.offsetBy(dx: 0.05, dy: 0), seconds: 3)
        XCTAssertEqual(f.crop, settled)
    }

    func testBriefMoveIsIgnored() {
        var f = Framing()
        run(&f, centred, seconds: 12)
        let settled = f.crop
        run(&f, centred.offsetBy(dx: 0.2, dy: 0), seconds: 0.5)
        run(&f, centred, seconds: 3)
        XCTAssertEqual(f.crop, settled)
    }

    func testBriefFaceLossIsIgnored() {
        var f = Framing()
        run(&f, centred, seconds: 12)
        let settled = f.crop
        run(&f, nil, seconds: 0.5)
        run(&f, centred, seconds: 3)
        XCTAssertEqual(f.crop, settled)
    }

    func testSustainedMoveIsFollowed() {
        var f = Framing()
        run(&f, centred, seconds: 12)
        let moved = centred.offsetBy(dx: 0.2, dy: 0)
        run(&f, moved, seconds: 10)
        XCTAssertEqual(f.crop.midX, moved.midX, accuracy: 0.01)
    }

    func testNoSubjectEasesToFullFrame() {
        var f = Framing()
        run(&f, centred, seconds: 8)
        run(&f, nil, seconds: 9)
        XCTAssertEqual(f.crop.minX, 0, accuracy: 0.01)
        XCTAssertEqual(f.crop.minY, 0, accuracy: 0.01)
        XCTAssertEqual(f.crop.width, 1, accuracy: 0.01)
        XCTAssertEqual(f.crop.height, 1, accuracy: 0.01)
    }

    func testTightnessZeroIsWiderThanOne() {
        var loose = Framing(), tight = Framing()
        run(&loose, centred, seconds: 8, tightness: 0)
        run(&tight, centred, seconds: 8, tightness: 1)
        XCTAssertGreaterThan(loose.crop.width, tight.crop.width)
    }

    func testFourThreeSourceKeeps16x9() {
        var f = Framing()
        run(&f, centred, seconds: 8, aspect: 4.0 / 3.0)
        XCTAssertEqual(f.crop.width * (4.0 / 3.0) / f.crop.height, wide, accuracy: 0.001)
    }
}
