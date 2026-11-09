import XCTest
import CoreGraphics
@testable import DarkfieldCore

/// The on-screen stack for `ids` (front to back), using each placed window's screen frame.
private func stack(_ placed: [PlacedWindow], _ ids: [CGWindowID]) -> [OnScreenWindow] {
    ids.compactMap { id in placed.first { $0.id == id }.map { OnScreenWindow(id: id, frame: $0.screenFrame) } }
}

final class PointerMapTests: XCTestCase {
    private let full = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testPointMapsIntoCanvas() {
        let placed = [PlacedWindow(id: 1, screenFrame: CGRect(x: 100, y: 100, width: 800, height: 450), canvasFrame: full)]
        XCTAssertEqual(PointerMap.canvasPoint(CGPoint(x: 500, y: 325), placed: placed, onScreen: stack(placed, [1])), CGPoint(x: 960, y: 540))
    }

    func testPointOutsideIsNil() {
        let placed = [PlacedWindow(id: 1, screenFrame: CGRect(x: 100, y: 100, width: 800, height: 450), canvasFrame: full)]
        XCTAssertNil(PointerMap.canvasPoint(CGPoint(x: 50, y: 50), placed: placed, onScreen: stack(placed, [1])))
    }

    func testFrontmostWins() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let placed = [
            PlacedWindow(id: 1, screenFrame: screen, canvasFrame: CGRect(x: 0, y: 0, width: 1000, height: 500)),
            PlacedWindow(id: 2, screenFrame: screen, canvasFrame: CGRect(x: 920, y: 580, width: 1000, height: 500)),
        ]
        XCTAssertEqual(PointerMap.canvasPoint(CGPoint(x: 10, y: 10), placed: placed, onScreen: stack(placed, [2, 1])), CGPoint(x: 930, y: 590))
        XCTAssertEqual(PointerMap.canvasPoint(CGPoint(x: 10, y: 10), placed: placed, onScreen: stack(placed, [1, 2])), CGPoint(x: 10, y: 10))
    }

    func testNegativeOriginDisplay() {
        let placed = [PlacedWindow(id: 7, screenFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1080), canvasFrame: full)]
        XCTAssertEqual(PointerMap.canvasPoint(CGPoint(x: -960, y: 340), placed: placed, onScreen: stack(placed, [7])), CGPoint(x: 960, y: 540))
    }

    func testToCG() {
        XCTAssertEqual(ScreenSpace.toCG(CGPoint(x: 10, y: 100), primaryHeight: 1117), CGPoint(x: 10, y: 1017))
    }

    func testRectToAppKit() {
        let cg = CGRect(x: 4000, y: 220, width: 960, height: 540)
        XCTAssertEqual(ScreenSpace.toAppKit(cg, primaryHeight: 2160), CGRect(x: 4000, y: 1400, width: 960, height: 540))
    }
}

final class PointerOcclusionTests: XCTestCase {
    func testNonSharedWindowInFrontHidesPointer() {
        let full = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let slides = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let placed = [PlacedWindow(id: 1, screenFrame: slides, canvasFrame: full)]
        let zoomToolbar = CGRect(x: 400, y: 0, width: 200, height: 40)
        let onScreen = [OnScreenWindow(id: 99, frame: zoomToolbar), OnScreenWindow(id: 1, frame: slides)]
        XCTAssertNil(PointerMap.canvasPoint(CGPoint(x: 450, y: 20), placed: placed, onScreen: onScreen))
        XCTAssertNotNil(PointerMap.canvasPoint(CGPoint(x: 100, y: 200), placed: placed, onScreen: onScreen))
    }

    func testOnlyAppLevelVisibleWindowsHideThePointer() {
        XCTAssertTrue(PointerMap.canHidePointer(layer: 0, alpha: 1))     // app window
        XCTAssertTrue(PointerMap.canHidePointer(layer: 3, alpha: 1))     // floating toolbar
        XCTAssertTrue(PointerMap.canHidePointer(layer: 8, alpha: 1))     // modal panel
        XCTAssertFalse(PointerMap.canHidePointer(layer: 0, alpha: 0))    // invisible
        XCTAssertFalse(PointerMap.canHidePointer(layer: 20, alpha: 1))   // Dock
        XCTAssertFalse(PointerMap.canHidePointer(layer: 23, alpha: 1))   // Notification Centre's full-display overlay
    }
}
