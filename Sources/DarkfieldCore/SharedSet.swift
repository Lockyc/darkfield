import CoreGraphics

/// Whether a shared window can be captured right now.
public enum Availability: Equatable, Sendable {
    case available, minimised, otherSpace, gone

    /// Why the window is off the canvas, as the panel shows it; nil when it is on.
    public var reason: String? {
        switch self {
        case .available: nil
        case .minimised: "Minimised — restore it to share"
        case .otherSpace: "On another Space"
        case .gone: "Closed"
        }
    }
}

public enum ToggleResult: Equatable, Sendable { case added, removed, refusedOwnWindow }

/// The windows the presenter has chosen, in the order they were added (or reordered to).
public struct SharedSet: Equatable, Sendable {
    public private(set) var ids: [CGWindowID] = []

    public init() {}

    /// Adds `id` if absent, removes it if present. darkfield's own windows are never shared.
    @discardableResult
    public mutating func toggle(_ id: CGWindowID, ownerPID: pid_t, selfPID: pid_t) -> ToggleResult {
        if ownerPID == selfPID { return .refusedOwnWindow }
        if let i = ids.firstIndex(of: id) {
            ids.remove(at: i)
            return .removed
        }
        ids.append(id)
        return .added
    }

    public mutating func move(from: Int, to: Int) {
        guard ids.indices.contains(from) else { return }
        let id = ids.remove(at: from)
        ids.insert(id, at: min(max(to, 0), ids.count))
    }

    public mutating func remove(_ id: CGWindowID) {
        ids.removeAll { $0 == id }
    }

    /// The ids that go on the canvas: only those currently `.available`, in set order.
    public func laidOut(availability: [CGWindowID: Availability]) -> [CGWindowID] {
        ids.filter { availability[$0] == .available }
    }
}
