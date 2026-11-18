/// The share window's properties, and whether the share rings show, parked or shown for a window
/// picker. Every one of them must flip together in both directions: one left behind makes the
/// window unpickable or leaves it in the presenter's way.
public struct ShareWindowTraits: Equatable, Sendable {
    /// Above normal windows. Never, parked or picking: Chromium's window picker lists only
    /// level-0 windows, and macOS's offers no raised window.
    public var raised: Bool
    /// Clicks pass through. macOS's picker offers no window that clicks pass through.
    public var ignoresMouse: Bool
    /// `.stationary`, which keeps the parked window still through Mission Control. macOS's picker
    /// offers no stationary window.
    public var stationary: Bool
    /// The amber rings over shared windows. Hidden while picking: a ring floats over the share
    /// window shown for picking, and macOS's click-to-pick picker offers no window under a raised one.
    public var ringsShown: Bool

    public static let parked = ShareWindowTraits(raised: false, ignoresMouse: true, stationary: true, ringsShown: true)

    /// The traits for the share window while `picking`. Only the Meeting output is shown for a
    /// picker; any other output keeps it parked.
    public static func `for`(picking: Bool, output: Output?) -> ShareWindowTraits {
        guard picking, output == .meeting else { return .parked }
        return ShareWindowTraits(raised: false, ignoresMouse: false, stationary: false, ringsShown: false)
    }
}
