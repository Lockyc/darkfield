import XCTest
@testable import DarkfieldCore

final class CameraSettingsTests: XCTestCase {
    func testCameraDefaults() {
        let c = Settings().camera
        XCTAssertNil(c.deviceID)
        XCTAssertNil(c.deviceName)
        XCTAssertTrue(c.blur)
        XCTAssertEqual(c.blurStrength, 0.7)
        XCTAssertTrue(c.framing)
        XCTAssertEqual(c.framingTightness, 0.5)
    }

    func testOldSettingsWithoutCameraKeepTheRest() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"margin": 12}"#.utf8))
        XCTAssertEqual(s.margin, 12)
        XCTAssertEqual(s.camera, CameraSettings())
    }

    func testPartialCameraKeepsTheRest() throws {
        let json = #"{"camera": {"deviceID": "usb1", "blurStrength": 0.2}}"#
        let c = try JSONDecoder().decode(Settings.self, from: Data(json.utf8)).camera
        XCTAssertEqual(c.deviceID, "usb1")
        XCTAssertEqual(c.blurStrength, 0.2)
        XCTAssertTrue(c.framing)
        XCTAssertEqual(c.framingTightness, 0.5)
    }

    func testCameraRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "darkfield-tests-\(UUID().uuidString)"))
        var s = Settings()
        s.camera = CameraSettings(deviceID: "usb1", deviceName: "EMEET SmartCam S600", blur: false,
                                  blurStrength: 0.1, framing: false, framingTightness: 0.9)
        s.save(to: defaults)
        XCTAssertEqual(Settings.load(from: defaults), s)
    }

    func testBlurRadiusRange() {
        XCTAssertEqual(BlurScale.radius(strength: 0, height: 1080), 21.6, accuracy: 0.01)
        XCTAssertEqual(BlurScale.radius(strength: 1, height: 1080), 64.8, accuracy: 0.01)
        XCTAssertEqual(BlurScale.radius(strength: 2, height: 1080), 64.8, accuracy: 0.01)
        XCTAssertEqual(BlurScale.radius(strength: -1, height: 1080), 21.6, accuracy: 0.01)
    }

    func testStaleSinkGoesDark() {
        let t = Date()
        XCTAssertTrue(IdleFrame.isStale(lastSinkFrame: nil, now: t))
        XCTAssertFalse(IdleFrame.isStale(lastSinkFrame: t, now: t.addingTimeInterval(0.4)))
        XCTAssertTrue(IdleFrame.isStale(lastSinkFrame: t, now: t.addingTimeInterval(0.6)))
    }
}
