import DarkfieldCore
import XCTest

final class ExtensionActivationTests: XCTestCase {
    private typealias Event = ExtensionActivation.Event
    private let version = "7"
    private let alphabet: [Event] = [.needsApproval, .activationFinished, .failed("x"), .deviceSeen, .deviceGone, .unseenTimeout]

    /// Every sequence over `alphabet` up to `length` events.
    private func sequences(upTo length: Int) -> [[Event]] {
        var all: [[Event]] = [[]]
        var frontier: [[Event]] = [[]]
        for _ in 0..<length {
            frontier = frontier.flatMap { s in alphabet.map { s + [$0] } }
            all += frontier
        }
        return all
    }

    /// Runs `events` across as many launches as the reducer asks for: a `.relaunch` starts a new
    /// process with only the persisted guards carried over, as `CameraRelay` does through
    /// UserDefaults. Calls `step` after each event with the live reducer and the action.
    private func run(_ events: [Event], relaunched: String?, repaired: String?,
                     step: (ExtensionActivation, Event, ExtensionActivation.Action) -> Void) {
        var a = ExtensionActivation(version: version, relaunchedVersion: relaunched, repairedVersion: repaired)
        for e in events {
            let action = a.handle(e)
            step(a, e, action)
            if action == .relaunch {
                a = ExtensionActivation(version: version, relaunchedVersion: a.relaunchedVersion, repairedVersion: a.repairedVersion)
            }
        }
    }

    func testInvariantsOverEverySequence() {
        continueAfterFailure = false
        let starts: [String?] = [nil, "6", version]
        for events in sequences(upTo: 6) {
            for relaunched in starts {
                for repaired in starts {
                    var relaunches = 0, deactivates = 0
                    var bothUsedBefore = relaunched == version && repaired == version
                    var seen = false
                    run(events, relaunched: relaunched, repaired: repaired) { a, event, action in
                        if event == .deviceSeen { seen = true }
                        if event == .deviceGone || action == .relaunch { seen = false }
                        if a.state == .ready {
                            XCTAssertTrue(seen, "ready without the device in view: \(events)")
                        }
                        if action == .relaunch { relaunches += 1 }
                        if action == .deactivate { deactivates += 1 }
                        if a.state == .needsRestart {
                            XCTAssertTrue(bothUsedBefore && a.relaunchedVersion == version && a.repairedVersion == version,
                                          "needsRestart before both remedies were spent: \(events) from \(String(describing: relaunched))/\(String(describing: repaired))")
                        }
                        bothUsedBefore = a.relaunchedVersion == version && a.repairedVersion == version
                    }
                    // One relaunch to see a new extension, plus one after the single repair.
                    XCTAssertLessThanOrEqual(deactivates, repaired == version ? 0 : 1, "\(events)")
                    XCTAssertLessThanOrEqual(relaunches, (relaunched == version ? 0 : 1) + deactivates, "\(events)")
                }
            }
        }
    }

    func testAnUpgradeWithNoLaunchdJobIsRepairedThenAsksForARestart() {
        // 78c8496: 0.2.0 installed over 0.1.0 was "activated enabled" with no job behind it.
        var a = ExtensionActivation(version: version, relaunchedVersion: "6", repairedVersion: "6")
        XCTAssertEqual(a.handle(.activationFinished), .awaitDevice)
        XCTAssertNotEqual(a.state, .ready, "ready on activation rather than on seeing the device")
        XCTAssertEqual(a.handle(.unseenTimeout), .relaunch)

        a = ExtensionActivation(version: version, relaunchedVersion: a.relaunchedVersion, repairedVersion: a.repairedVersion)
        XCTAssertEqual(a.handle(.activationFinished), .awaitDevice)
        XCTAssertEqual(a.handle(.unseenTimeout), .deactivate)
        XCTAssertEqual(a.handle(.activationFinished), .reactivate)
        XCTAssertEqual(a.handle(.activationFinished), .relaunch)

        a = ExtensionActivation(version: version, relaunchedVersion: a.relaunchedVersion, repairedVersion: a.repairedVersion)
        XCTAssertEqual(a.handle(.activationFinished), .awaitDevice)
        XCTAssertEqual(a.handle(.unseenTimeout), .none)
        XCTAssertEqual(a.state, .needsRestart)
    }

    func testAReplacedExtensionsDeviceGoingAwayIsNotReady() {
        var a = ExtensionActivation(version: version)
        _ = a.handle(.deviceSeen)
        _ = a.handle(.deviceGone)
        XCTAssertEqual(a.state, .activating)
    }

    func testADeviceSeenInTimeNeedsNoRelaunch() {
        var a = ExtensionActivation(version: version)
        XCTAssertEqual(a.handle(.activationFinished), .awaitDevice)
        XCTAssertEqual(a.handle(.deviceSeen), .none)
        XCTAssertEqual(a.state, .ready)
        XCTAssertEqual(a.handle(.unseenTimeout), .none)
        XCTAssertNil(a.relaunchedVersion)
    }
}
