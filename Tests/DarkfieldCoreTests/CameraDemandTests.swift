import XCTest
@testable import DarkfieldCore

final class CameraDemandTests: XCTestCase {
    private let usb = CameraInfo(id: "usb1", name: "EMEET SmartCam S600")
    private let mac = CameraInfo(id: "mac", name: "MacBook Pro Camera")
    private let phone = CameraInfo(id: "phone", name: "Lachlan's iPhone Camera")

    private func streaming() -> CameraDemand {
        var d = CameraDemand()
        d.clientStreaming = true
        return d
    }

    func testIdleIsOff() {
        let d = CameraDemand()
        XCTAssertNil(d.source(preferred: [usb], connected: [usb]))
        XCTAssertEqual(d.status(preferred: [usb], connected: [usb]), .off)
    }

    func testClientStartsCamera() {
        let d = streaming()
        XCTAssertEqual(d.source(preferred: [usb], connected: [usb]), usb)
        XCTAssertEqual(d.status(preferred: [usb], connected: [usb]), .live)
    }

    func testPreviewStartsCamera() {
        var d = CameraDemand()
        d.panelOpen = true
        d.preview = true
        XCTAssertEqual(d.source(preferred: [usb], connected: [usb]), usb)
    }

    func testPanelCloseEndsPreview() {
        var d = CameraDemand()
        d.panelOpen = true
        d.preview = true
        d.panelClosed()
        XCTAssertFalse(d.preview)
        XCTAssertNil(d.source(preferred: [usb], connected: [usb]))
        XCTAssertEqual(d.status(preferred: [usb], connected: [usb]), .off)
    }

    func testPanelCloseKeepsACallRunning() {
        var d = streaming()
        d.preview = true
        d.panelClosed()
        XCTAssertEqual(d.source(preferred: [usb], connected: [usb]), usb)
    }

    func testFirstPreferenceWinsWhenConnected() {
        let d = streaming()
        XCTAssertEqual(d.source(preferred: [usb, mac], connected: [phone, mac, usb]), usb)
        XCTAssertEqual(d.status(preferred: [usb, mac], connected: [phone, mac, usb]), .live)
    }

    func testFallsBackToTheNextPreferenceNeverAnUnlistedCamera() {
        let d = streaming()
        XCTAssertEqual(d.source(preferred: [usb, mac], connected: [phone, mac]), mac)
        XCTAssertEqual(d.status(preferred: [usb, mac], connected: [phone, mac]),
                       .fallback(missing: "EMEET SmartCam S600", using: "MacBook Pro Camera"))
    }

    func testNoPreferenceConnectedGoesDarkAndNamesTheFirst() {
        let d = streaming()
        XCTAssertNil(d.source(preferred: [usb, mac], connected: [phone]))
        XCTAssertEqual(d.status(preferred: [usb, mac], connected: [phone]), .missing(name: "EMEET SmartCam S600"))
    }

    func testNoCameraChosen() {
        let d = streaming()
        XCTAssertNil(d.source(preferred: [], connected: [usb]))
        XCTAssertEqual(d.status(preferred: [], connected: [usb]), .noCameraChosen)
    }
}

final class CameraChoiceTests: XCTestCase {
    func testExcludesDarkfieldCamera() {
        let all = [CameraInfo(id: "a", name: "FaceTime HD Camera"),
                   CameraInfo(id: "b", name: "Darkfield Camera"),
                   CameraInfo(id: "c", name: "EMEET SmartCam S600")]
        XCTAssertEqual(CameraChoice.selectable(all).map(\.id), ["a", "c"])
    }
}

/// SplitMix64: a seeded generator, so a failing sequence can be replayed from its seed.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class CameraDemandSequenceTests: XCTestCase {
    private let cameras = (0..<4).map { CameraInfo(id: "cam\($0)", name: "Camera \($0)") }

    /// Random event sequences, the ones the app can produce: the Preview toggle lives in the
    /// panel, so it changes only while the panel is open. After every step the camera that runs is
    /// checked against a direct reading of CLAUDE.md's rule.
    func testTheCameraFollowsDemandAndPreferenceOverEverySequence() {
        continueAfterFailure = false
        for seed in UInt64(1)...500 {
            var rng = SeededGenerator(state: seed)
            var demand = CameraDemand()
            var settings = CameraSettings()
            var connected: [CameraInfo] = []
            var remembered: Set<String> = []
            var trace: [String] = []
            for _ in 0..<20 {
                switch Int.random(in: 0..<7, using: &rng) {
                case 0:
                    demand.panelOpen = true
                    trace.append("panelOpened")
                case 1:
                    demand.panelClosed()
                    trace.append("panelClosed")
                case 2:
                    guard demand.panelOpen else { continue }
                    demand.preview.toggle()
                    trace.append("preview=\(demand.preview)")
                case 3:
                    demand.clientStreaming.toggle()
                    trace.append("clientStreaming=\(demand.clientStreaming)")
                case 4:
                    let c = cameras.randomElement(using: &rng)!
                    guard !connected.contains(c) else { continue }
                    connected.append(c)
                    settings.remember(connected)
                    trace.append("plug \(c.id)")
                case 5:
                    guard let c = connected.randomElement(using: &rng) else { continue }
                    connected.removeAll { $0 == c }
                    trace.append("unplug \(c.id)")
                default:
                    let choice = settings.known.shuffled(using: &rng)
                    settings.preferred = Array(choice.prefix(Int.random(in: 0...choice.count, using: &rng)))
                    trace.append("prefer \(settings.preferred.map(\.id))")
                }
                remembered.formUnion(connected.map(\.id))

                let why = "seed \(seed): \(trace)"
                let source = demand.source(preferred: settings.preferred, connected: connected)
                let wanted = demand.clientStreaming || (demand.preview && demand.panelOpen)
                if !wanted {
                    XCTAssertNil(source, "camera on with no demand, \(why)")
                } else {
                    let expected = settings.preferred.first { connected.contains($0) }
                    XCTAssertEqual(source, expected, "not the first connected preference, \(why)")
                }
                if let source {
                    XCTAssertTrue(settings.preferred.contains(source), "a camera the presenter didn't choose, \(why)")
                }
                XCTAssertTrue(remembered.isSubset(of: settings.known.map(\.id)), "a remembered camera was forgotten, \(why)")
                if !demand.panelOpen { XCTAssertFalse(demand.preview, "preview outlived the panel, \(why)") }
            }
        }
    }
}
