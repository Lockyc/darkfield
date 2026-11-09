import CoreGraphics

/// Whether a shared window can be captured right now.
public enum Availability: Equatable, Sendable {
    /// Windows on another Space still stream, so they count as available; a closed window leaves
    /// the set rather than lingering as a state.
    case available, minimised

    /// Why the window is off the canvas, as the panel shows it; nil when it is on.
    public var reason: String? {
        switch self {
        case .available: nil
        case .minimised: "Minimised — restore it to share"
        }
    }
}

public enum ToggleResult: Equatable, Sendable { case added, removed, refusedOwnWindow }

/// The windows the presenter has chosen, in the order they were added.
public struct SharedSet: Equatable, Sendable {
    public private(set) var ids: [CGWindowID] = []
    /// Counts additions; a window-list snapshot records it so `prune` can tell which windows the
    /// snapshot could have seen.
    public private(set) var generation = 0
    private var addedAt: [CGWindowID: Int] = [:]

    public init() {}

    /// Adds `id` if absent, removes it if present. darkfield's own windows are never shared.
    @discardableResult
    public mutating func toggle(_ id: CGWindowID, ownerPID: pid_t, selfPID: pid_t) -> ToggleResult {
        if ownerPID == selfPID { return .refusedOwnWindow }
        if ids.contains(id) {
            remove(id)
            return .removed
        }
        generation += 1
        ids.append(id)
        addedAt[id] = generation
        return .added
    }

    /// Removes windows absent from a window list taken at `snapshot` (a past `generation`). A window
    /// added after the snapshot is kept: the list was fetched before it could appear.
    public mutating func prune(present: Set<CGWindowID>, snapshot: Int) {
        for id in ids where !present.contains(id) && (addedAt[id] ?? 0) <= snapshot { remove(id) }
    }

    public mutating func remove(_ id: CGWindowID) {
        ids.removeAll { $0 == id }
        addedAt[id] = nil
    }

    /// The ids that go on the canvas: only those currently `.available`, in set order.
    public func laidOut(availability: [CGWindowID: Availability]) -> [CGWindowID] {
        ids.filter { availability[$0] == .available }
    }
}
