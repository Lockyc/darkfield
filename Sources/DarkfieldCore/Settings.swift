import CoreGraphics
import Foundation

/// What the canvas background shows.
public enum WallpaperSource: Codable, Equatable, Sendable {
    case primary
    case display(CGDirectDisplayID)
    case image(URL)
}

/// Where the canvas goes. One output at a time.
public enum Output: Codable, Equatable, Sendable {
    case meeting
    case projector(CGDirectDisplayID)
}

public struct Settings: Codable, Equatable, Sendable {
    public var windowHotKey: HotKeySpec? = .defaultWindowToggle
    /// Global hotkeys other than the window toggle ship unassigned.
    public var pointerHotKey: HotKeySpec? = nil
    /// Seconds of stillness before the audience pointer fades; nil = never.
    public var idleFade: TimeInterval? = 10
    public var margin: CGFloat = 40
    public var layout: LayoutMode = .fill
    public var wallpaper: WallpaperSource = .primary
    public var output: Output = .meeting
    public var pointerEnabled = true

    public init() {}

    static let key = "settings"

    /// The saved settings, or the defaults when none are saved or they no longer decode.
    public static func load(from defaults: UserDefaults) -> Settings {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}
