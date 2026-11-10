import XCTest
import CoreGraphics
@testable import DarkfieldCore

final class LayoutTests: XCTestCase {
    private func frames(_ sizes: [CGSize], margin: CGFloat = 0) -> [CGRect] {
        Layout.frames(sources: sizes.map { CGRect(origin: .zero, size: $0) }, margin: margin)
    }

    func testMeetingMinimumIsTheCanvasInPixels() {
        XCTAssertEqual(Layout.meetingMinimum(backingScale: 1), CGSize(width: 1920, height: 1080))
        XCTAssertEqual(Layout.meetingMinimum(backingScale: 2), CGSize(width: 960, height: 540))
    }

    func testSingleFillsWithZeroMargin() {
        XCTAssertEqual(frames([CGSize(width: 1600, height: 900)]), [CGRect(x: 0, y: 0, width: 1920, height: 1080)])
    }

    func testSingleAspectFits() {
        XCTAssertEqual(frames([CGSize(width: 1000, height: 1000)]), [CGRect(x: 420, y: 0, width: 1080, height: 1080)])
    }

    func testEveryWindowFillsTheCanvasOnItsOwn() {
        let r = frames([CGSize(width: 1600, height: 900), CGSize(width: 1000, height: 1000)])
        XCTAssertEqual(r, [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 420, y: 0, width: 1080, height: 1080)])
    }

    func testMarginInsets() {
        let r = frames([CGSize(width: 1600, height: 900)], margin: 40)[0]
        XCTAssertEqual(r.minY, 40, accuracy: 0.001)
        XCTAssertEqual(r.height, 1000, accuracy: 0.001)
        XCTAssertEqual(r.midX, 960, accuracy: 0.001)
    }

    func testLayoutUsesCurrentSizes() {
        XCTAssertNotEqual(frames([CGSize(width: 800, height: 600)]), frames([CGSize(width: 1600, height: 900)]))
    }

    func testEmptyIsEmpty() {
        XCTAssertEqual(frames([]), [])
    }

    func testStackOrdersBackToFrontByScreenStacking() {
        // On screen, 3 is in front of 1; 2 is off screen (another Space), so it goes to the back.
        XCTAssertEqual(Layout.backToFront([1, 2, 3], frontToBack: [9, 3, 7, 1]), [2, 1, 3])
    }

    func testStackKeepsSharedOrderForWindowsOffScreen() {
        XCTAssertEqual(Layout.backToFront([4, 5, 1], frontToBack: [1]), [4, 5, 1])
    }
}
