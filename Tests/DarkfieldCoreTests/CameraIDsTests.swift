import XCTest
@testable import DarkfieldCore

final class CameraIDsTests: XCTestCase {
    /// The extension publishes the property by name and darkfield reads it by selector; they must
    /// name the same four-character code.
    func testClientsSelectorMatchesPropertyName() {
        let code = CameraIDs.clientsProperty.split(separator: "_")[1]
        let selector = code.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        XCTAssertEqual(selector, CameraIDs.clientsSelector)
    }

    func testStreamsAreDistinct() {
        XCTAssertEqual(Set([CameraIDs.device, CameraIDs.sourceStream, CameraIDs.sinkStream]).count, 3)
    }
}
