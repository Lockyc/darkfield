import XCTest
import CoreGraphics
@testable import DarkfieldCore

final class PointerMapTests: XCTestCase {
    private let full = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testPointMapsIntoCanvas() {
        let placed = [PlacedWindow(id: 1, screenFrame: CGRect(x: 100, y: 100, width: 800, height: 450), canvasFrame: full)]
        XCTAssertEqual(PointerMap.canvasPoint(CGPoint(x: 500, y: 325), placed: placed, zOrder: [1]), CGPoint(x: 960, y: 540))
    }

    func testPointOutsideIsNil() {
        let placed = [PlacedWindow(id: 1, screenFrame: CGRect(x: 100, y: 100, width: 800, height: 450), canvasFrame: full)]
        XCTAssertNil(PointerMap.canvasPoint(CGPoint(x: 50, y: 50), placed: placed, zOrder: [1]))
    }

    func testFrontmostWins() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let placed = [
            PlacedWindow(id: 1, screenFrame: screen, canvasFrame: CGRect(x: 0, y: 0, width: 1000, height: 500)),
            PlacedWindow(id: 2, screenFrame: screen, canvasFrame: CGRect(x: 920, y: 580, width: 1000, height: 500)),
        ]
        XCTAssertEqual(PointerMap.canvasPoint(CGPoint(x: 10, y: 10), placed: placed, zOrder: [2, 1]), CGPoint(x: 930, y: 590))
        XCTAssertEqual(PointerMap.canvasPoint(CGPoint(x: 10, y: 10), placed: placed, zOrder: [1, 2]), CGPoint(x: 10, y: 10))
    }

    func testNegativeOriginDisplay() {
        let placed = [PlacedWindow(id: 7, screenFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1080), canvasFrame: full)]
        XCTAssertEqual(PointerMap.canvasPoint(CGPoint(x: -960, y: 340), placed: placed, zOrder: [7]), CGPoint(x: 960, y: 540))
    }

    func testToCG() {
        XCTAssertEqual(ScreenSpace.toCG(CGPoint(x: 10, y: 100), primaryHeight: 1117), CGPoint(x: 10, y: 1017))
    }
}
