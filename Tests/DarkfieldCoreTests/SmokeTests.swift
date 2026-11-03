import XCTest
@testable import DarkfieldCore

final class SmokeTests: XCTestCase {
    func testCoreLinks() {
        XCTAssertNotNil(DarkfieldCore.self)
    }
}
