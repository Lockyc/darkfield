import XCTest
@testable import DarkfieldCore

final class SettingsTests: XCTestCase {
    func testDefaultsMatchSpec() {
        let s = Settings()
        XCTAssertEqual(s.windowHotKey?.keyCode, 18)         // kVK_ANSI_1
        XCTAssertEqual(s.windowHotKey?.modifiers, 0x300)    // cmdKey | shiftKey
        XCTAssertEqual(s.windowHotKey?.display, "⇧⌘1")
        XCTAssertEqual(s.fitHotKey?.keyCode, 19)            // kVK_ANSI_2
        XCTAssertEqual(s.fitHotKey?.modifiers, 0x300)
        XCTAssertEqual(s.fitHotKey?.display, "⇧⌘2")
        XCTAssertNil(s.pointerHotKey)
        XCTAssertEqual(s.idleFade, 10)
        XCTAssertEqual(s.margin, 40)
        XCTAssertEqual(s.wallpaper, .primary)
        XCTAssertEqual(s.output, .meeting)
        XCTAssertTrue(s.pointerEnabled)
    }

    func testSettingsRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "darkfield-tests-\(UUID().uuidString)"))
        var s = Settings()
        s.idleFade = nil
        s.output = .projector(42)
        s.wallpaper = .image(URL(fileURLWithPath: "/tmp/x.png"))
        s.pointerHotKey = HotKeySpec(keyCode: 35, modifiers: 0x800 | 0x1000, display: "⌃⌥P")
        s.save(to: defaults)
        XCTAssertEqual(Settings.load(from: defaults), s)
    }

    func testMissingOrCorruptLoadsDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "darkfield-tests-\(UUID().uuidString)"))
        XCTAssertEqual(Settings.load(from: defaults), Settings())
        defaults.set(Data("nonsense".utf8), forKey: "settings")
        XCTAssertEqual(Settings.load(from: defaults), Settings())
    }
}

final class SettingsMigrationTests: XCTestCase {
    func testMissingFieldsTakeDefaultsAndKeepTheRest() throws {
        let json = #"{"margin": 12, "layout": "mirror"}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(s.margin, 12)
        XCTAssertEqual(s.windowHotKey, .defaultWindowToggle)
        XCTAssertEqual(s.fitHotKey, .defaultFitWindow)
        XCTAssertEqual(s.idleFade, 10)
    }

    func testExplicitNullsSurvive() throws {
        var s = Settings()
        s.idleFade = nil
        s.windowHotKey = nil
        s.fitHotKey = nil
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        XCTAssertNil(back.idleFade)
        XCTAssertNil(back.windowHotKey)
        XCTAssertNil(back.fitHotKey)
    }
}
