import XCTest
@testable import DarkfieldCore

final class CameraDemandTests: XCTestCase {
    private let usb = CameraInfo(id: "usb1", name: "EMEET SmartCam S600")

    func testIdleIsOff() {
        let d = CameraDemand()
        XCTAssertFalse(d.shouldRun(chosen: "usb1", connected: [usb]))
        XCTAssertEqual(d.status(chosenID: "usb1", chosenName: usb.name, connected: [usb]), .off)
    }

    func testClientStartsCamera() {
        var d = CameraDemand()
        d.clientStreaming = true
        XCTAssertTrue(d.shouldRun(chosen: "usb1", connected: [usb]))
        XCTAssertEqual(d.status(chosenID: "usb1", chosenName: usb.name, connected: [usb]), .live)
    }

    func testPreviewStartsCamera() {
        var d = CameraDemand()
        d.panelOpen = true
        d.preview = true
        XCTAssertTrue(d.shouldRun(chosen: "usb1", connected: [usb]))
    }

    func testPanelCloseEndsPreview() {
        var d = CameraDemand()
        d.panelOpen = true
        d.preview = true
        d.panelClosed()
        XCTAssertFalse(d.preview)
        XCTAssertFalse(d.shouldRun(chosen: "usb1", connected: [usb]))
        XCTAssertEqual(d.status(chosenID: "usb1", chosenName: usb.name, connected: [usb]), .off)
    }

    func testPanelCloseKeepsACallRunning() {
        var d = CameraDemand()
        d.clientStreaming = true
        d.preview = true
        d.panelClosed()
        XCTAssertTrue(d.shouldRun(chosen: "usb1", connected: [usb]))
    }

    func testMissingCameraGoesDarkAndNamesIt() {
        var d = CameraDemand()
        d.clientStreaming = true
        XCTAssertFalse(d.shouldRun(chosen: "usb1", connected: []))
        XCTAssertEqual(d.status(chosenID: "usb1", chosenName: usb.name, connected: []), .missing(name: "EMEET SmartCam S600"))
        XCTAssertTrue(d.shouldRun(chosen: "usb1", connected: [usb]))
    }

    func testMissingWithoutSavedName() {
        var d = CameraDemand()
        d.clientStreaming = true
        XCTAssertEqual(d.status(chosenID: "usb1", chosenName: nil, connected: []), .missing(name: "The chosen camera"))
    }

    func testNoCameraChosen() {
        var d = CameraDemand()
        d.clientStreaming = true
        XCTAssertFalse(d.shouldRun(chosen: nil, connected: [usb]))
        XCTAssertEqual(d.status(chosenID: nil, chosenName: nil, connected: [usb]), .noCameraChosen)
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
