import Foundation

public struct CameraInfo: Codable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum CameraChoice {
    /// The cameras the presenter can pick as Darkfield Camera's source. Darkfield Camera itself
    /// is never one: it would feed its own output back into itself.
    public static func selectable(_ all: [CameraInfo]) -> [CameraInfo] {
        all.filter { $0.name != CameraIDs.deviceName }
    }
}

public enum CameraStatus: Equatable, Sendable {
    case off
    case live
    /// The first choice isn't connected, so a later one is running.
    case fallback(missing: String, using: String)
    /// None of the chosen cameras is connected.
    case missing(name: String)
    case noCameraChosen
}

/// Whether the physical camera runs, and which. It runs only while a call streams from Darkfield
/// Camera or the panel's Preview is on, and only from the presenter's chosen cameras: the first of
/// them that is connected, never one they didn't choose.
public struct CameraDemand: Equatable, Sendable {
    public var clientStreaming = false
    public var preview = false
    public var panelOpen = false

    public init() {}

    /// Preview lasts only while the panel is open, so closing it never leaves the camera on.
    public mutating func panelClosed() {
        panelOpen = false
        preview = false
    }

    var wanted: Bool { clientStreaming || preview }

    /// The camera to run: the first of `preferred` that is connected, or nil to run none.
    public func source(preferred: [CameraInfo], connected: [CameraInfo]) -> CameraInfo? {
        guard wanted else { return nil }
        return preferred.first { p in connected.contains { $0.id == p.id } }
    }

    public func status(preferred: [CameraInfo], connected: [CameraInfo]) -> CameraStatus {
        guard wanted else { return .off }
        guard let first = preferred.first else { return .noCameraChosen }
        guard let using = source(preferred: preferred, connected: connected) else { return .missing(name: first.name) }
        return using == first ? .live : .fallback(missing: first.name, using: using.name)
    }
}
