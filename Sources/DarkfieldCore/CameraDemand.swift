import Foundation

public struct CameraInfo: Equatable, Sendable {
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
    case missing(name: String)
    case noCameraChosen
}

/// Whether the physical camera runs. It runs only while a call streams from Darkfield Camera or
/// the panel's Preview is on, and only from the camera the presenter chose — never a fallback.
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

    public func shouldRun(chosen: String?, connected: [CameraInfo]) -> Bool {
        guard wanted, let chosen else { return false }
        return connected.contains { $0.id == chosen }
    }

    public func status(chosenID: String?, chosenName: String?, connected: [CameraInfo]) -> CameraStatus {
        guard wanted else { return .off }
        guard let chosenID else { return .noCameraChosen }
        guard connected.contains(where: { $0.id == chosenID }) else {
            return .missing(name: chosenName ?? "The chosen camera")
        }
        return .live
    }
}
