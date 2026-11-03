import XCTest
@testable import DarkfieldCore

final class SharedSetTests: XCTestCase {
    private let me: pid_t = 100
    private let other: pid_t = 200

    func testToggleAddsThenRemoves() {
        var s = SharedSet()
        XCTAssertEqual(s.toggle(5, ownerPID: other, selfPID: me), .added)
        XCTAssertEqual(s.ids, [5])
        XCTAssertEqual(s.toggle(5, ownerPID: other, selfPID: me), .removed)
        XCTAssertEqual(s.ids, [])
    }

    func testOwnWindowRefused() {
        var s = SharedSet()
        XCTAssertEqual(s.toggle(5, ownerPID: me, selfPID: me), .refusedOwnWindow)
        XCTAssertEqual(s.ids, [])
    }

    func testMoveReorders() {
        var s = SharedSet()
        for id: CGWindowID in [1, 2, 3] { s.toggle(id, ownerPID: other, selfPID: me) }
        s.move(from: 2, to: 0)
        XCTAssertEqual(s.ids, [3, 1, 2])
    }

    func testUnavailableExcludedFromLayout() {
        var s = SharedSet()
        for id: CGWindowID in [1, 2, 3] { s.toggle(id, ownerPID: other, selfPID: me) }
        XCTAssertEqual(s.laidOut(availability: [1: .available, 2: .minimised, 3: .available]), [1, 3])
    }

    func testUnknownAvailabilityIsExcluded() {
        var s = SharedSet()
        s.toggle(1, ownerPID: other, selfPID: me)
        XCTAssertEqual(s.laidOut(availability: [:]), [])
    }

    func testWindowGoneIsRemoved() {
        var s = SharedSet()
        for id: CGWindowID in [1, 2, 3] { s.toggle(id, ownerPID: other, selfPID: me) }
        s.remove(2)
        XCTAssertEqual(s.ids, [1, 3])
    }

    func testAvailabilityReasons() {
        XCTAssertNil(Availability.available.reason)
        XCTAssertEqual(Availability.minimised.reason, "Minimised — restore it to share")
    }
}

final class SharedSetPruneTests: XCTestCase {
    func testPruneKeepsWindowsAddedAfterTheSnapshot() {
        var s = SharedSet()
        s.toggle(1, ownerPID: 2, selfPID: 1)
        let snapshot = s.generation
        s.toggle(7, ownerPID: 2, selfPID: 1)          // added after the content fetch began
        s.prune(present: [], snapshot: snapshot)
        XCTAssertEqual(s.ids, [7])
    }
}
