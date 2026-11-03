import XCTest
import CoreGraphics
@testable import DarkfieldCore

final class LayoutTests: XCTestCase {
    private func fill(_ sizes: [CGSize], margin: CGFloat = 0) -> [CGRect] {
        Layout.frames(sources: sizes.map { CGRect(origin: .zero, size: $0) }, mode: .fill, margin: margin)
    }

    func testSingleFillsWithZeroMargin() {
        XCTAssertEqual(fill([CGSize(width: 1600, height: 900)]), [CGRect(x: 0, y: 0, width: 1920, height: 1080)])
    }

    func testSingleAspectFits() {
        XCTAssertEqual(fill([CGSize(width: 1000, height: 1000)]), [CGRect(x: 420, y: 0, width: 1080, height: 1080)])
    }

    func testTwoSideBySide() {
        let s = CGSize(width: 800, height: 450)
        XCTAssertEqual(fill([s, s]), [
            CGRect(x: 0, y: 270, width: 960, height: 540),
            CGRect(x: 960, y: 270, width: 960, height: 540),
        ])
    }

    func testThreeIsTwoByTwoGrid() {
        let s = CGSize(width: 1600, height: 900)
        let r = fill([s, s, s])
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r[0], CGRect(x: 0, y: 0, width: 960, height: 540))
        XCTAssertEqual(r[1], CGRect(x: 960, y: 0, width: 960, height: 540))
        XCTAssertEqual(r[2], CGRect(x: 0, y: 540, width: 960, height: 540))
    }

    func testMarginInsetsAndGaps() {
        let s = CGSize(width: 800, height: 450)
        let r = fill([s, s], margin: 40)
        XCTAssertEqual(r[0].minX, 40, accuracy: 0.001)
        XCTAssertEqual(r[1].minX, r[0].maxX + 40, accuracy: 0.001)
    }

    func testMirrorKeepsRelativePositions() {
        let a = CGRect(x: 0, y: 0, width: 960, height: 540)
        let b = CGRect(x: 960, y: 540, width: 960, height: 540)
        XCTAssertEqual(Layout.frames(sources: [a, b], mode: .mirror, margin: 0), [a, b])
    }

    func testMirrorAcrossDisplays() {
        let r = Layout.frames(sources: [
            CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
        ], mode: .mirror, margin: 0)
        XCTAssertEqual(r, [
            CGRect(x: 0, y: 270, width: 960, height: 540),
            CGRect(x: 960, y: 270, width: 960, height: 540),
        ])
    }

    func testLayoutUsesCurrentSizes() {
        XCTAssertNotEqual(fill([CGSize(width: 800, height: 600)]), fill([CGSize(width: 1600, height: 900)]))
    }

    func testEmptyIsEmpty() {
        XCTAssertEqual(fill([]), [])
        XCTAssertEqual(Layout.frames(sources: [], mode: .mirror, margin: 0), [])
    }
}
