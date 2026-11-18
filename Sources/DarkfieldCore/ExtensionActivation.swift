import Foundation

/// The decisions behind bringing Darkfield Camera's system extension up, as a reducer over what
/// the system reports. `CameraRelay` feeds it events, persists `relaunchedVersion` and
/// `repairedVersion` across launches, and carries out the action it returns.
///
/// A process that is already running never sees a camera that a newly installed or replaced
/// extension publishes; only a new process does. So once activation succeeds, darkfield relaunches
/// if the device is still unseen when `unseenTimeout` arrives, at most once per extension version,
/// so a device that never appears can't cause a relaunch loop.
///
/// An upgrade can leave the new version "activated enabled" with no launchd job behind it (launchd
/// refuses the new job while the old one is still going away), so nothing ever starts it. When the
/// device is still missing after that relaunch, darkfield deactivates and reactivates the extension
/// once per version, which registers the job again, then relaunches to see it. If that fails too,
/// only a restart brings the camera up.
public struct ExtensionActivation: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// This build carries no extension. Set by the driver before any event; no event leaves it.
        case notInThisBuild
        case activating
        case needsApproval
        /// The device is visible: video apps can pick Darkfield Camera.
        case ready
        /// Installed, but macOS isn't running it; a restart registers it again.
        case needsRestart
        case failed(String)
    }

    public enum Event: Equatable, Sendable {
        case needsApproval
        /// The system extension request (activation or deactivation) succeeded.
        case activationFinished
        case failed(String)
        case deviceSeen
        /// The device is listed but can't carry frames.
        case deviceUnusable(String)
        case deviceGone
        /// The wait armed by `.awaitDevice` has run out.
        case unseenTimeout
    }

    public enum Action: Equatable, Sendable {
        case none
        /// Start a new process, which can see a newly published device.
        case relaunch
        /// Submit a deactivation request; its result arrives as `activationFinished`.
        case deactivate
        /// Submit an activation request.
        case reactivate
        /// Wait a while for the device, then send `unseenTimeout`.
        case awaitDevice
    }

    public private(set) var state: State = .activating
    /// The extension version this process (or an earlier launch) relaunched to see.
    public private(set) var relaunchedVersion: String?
    /// The extension version darkfield deactivated and reactivated to register again.
    public private(set) var repairedVersion: String?
    public let version: String
    public private(set) var deviceVisible = false
    /// A repair's deactivation is in flight, so its result starts the reactivation.
    private var repairing = false
    /// This process has reactivated the extension.
    private var reactivated = false

    public init(version: String, relaunchedVersion: String? = nil, repairedVersion: String? = nil) {
        self.version = version
        self.relaunchedVersion = relaunchedVersion
        self.repairedVersion = repairedVersion
    }

    public mutating func handle(_ event: Event) -> Action {
        switch event {
        case .needsApproval:
            state = .needsApproval
            return .none
        case .failed(let message):
            repairing = false
            state = .failed(message)
            return .none
        case .deviceSeen:
            deviceVisible = true
            state = .ready
            return .none
        case .deviceUnusable(let message):
            deviceVisible = true
            state = .failed(message)
            return .none
        case .deviceGone:
            deviceVisible = false
            if state == .ready { state = .activating }
            return .none
        case .activationFinished:
            if repairing {
                repairing = false
                reactivated = true
                return .reactivate
            }
            // This process can't see the reactivated extension's device until it relaunches.
            if reactivated, !deviceVisible { return .relaunch }
            return .awaitDevice
        case .unseenTimeout:
            guard !deviceVisible else { return .none }
            if relaunchedVersion != version {
                relaunchedVersion = version
                return .relaunch
            }
            if repairedVersion != version {
                repairedVersion = version
                repairing = true
                return .deactivate
            }
            state = .needsRestart
            return .none
        }
    }
}
