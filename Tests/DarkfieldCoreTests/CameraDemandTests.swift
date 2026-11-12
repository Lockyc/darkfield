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
