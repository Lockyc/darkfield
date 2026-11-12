import CoreGraphics
import Foundation

/// What the canvas background shows.
public enum WallpaperSource: Codable, Hashable, Sendable {
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
    public var wallpaper: WallpaperSource = .primary
    public var output: Output = .meeting
    public var pointerEnabled = true
    public var camera = CameraSettings()

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case windowHotKey, pointerHotKey, idleFade, margin, wallpaper, output, pointerEnabled, camera
    }

    /// Field by field: a key missing from older saved settings takes its default and the rest
    /// survive; a key saved as null stays nil.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func field<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        func optional<T: Decodable>(_ key: CodingKeys, _ fallback: T?) -> T? {
            guard c.contains(key) else { return fallback }
            return try? c.decodeIfPresent(T.self, forKey: key)
        }
        windowHotKey = optional(.windowHotKey, windowHotKey)
        pointerHotKey = optional(.pointerHotKey, pointerHotKey)
        idleFade = optional(.idleFade, idleFade)
        margin = field(.margin, margin)
        wallpaper = field(.wallpaper, wallpaper)
        output = field(.output, output)
        pointerEnabled = field(.pointerEnabled, pointerEnabled)
        camera = field(.camera, camera)
    }

    /// Writes every key, nil as null, so a deliberately cleared value is not mistaken for a
    /// missing one on the next launch.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(windowHotKey, forKey: .windowHotKey)
        try c.encode(pointerHotKey, forKey: .pointerHotKey)
        try c.encode(idleFade, forKey: .idleFade)
        try c.encode(margin, forKey: .margin)
        try c.encode(wallpaper, forKey: .wallpaper)
        try c.encode(output, forKey: .output)
        try c.encode(pointerEnabled, forKey: .pointerEnabled)
        try c.encode(camera, forKey: .camera)
    }

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
