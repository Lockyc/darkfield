import CoreGraphics
import Foundation

/// Darkfield Camera's auto-framing: a 16:9 crop of the source that follows the presenter the
/// way Center Stage does — a slow, damped zoom and pan that ignores small movements.
///
/// Rects are normalized source coordinates with a top-left origin (0…1). The crop always lies
/// inside the source, and `crop` is the full source until the first `step`.
public struct Framing {
    public private(set) var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// The framing the crop is easing towards. A new target replaces it only from outside the
    /// dead zone, so the shot holds still while the presenter shifts in their seat.
    private var goal: (cx: CGFloat, cy: CGFloat, w: CGFloat)?
    private var current: (cx: CGFloat, cy: CGFloat, w: CGFloat)?

    static let halfLife: TimeInterval = 0.6
    static let deadZoneCentre: CGFloat = 0.08
    static let deadZoneWidth: CGFloat = 0.10
    /// Within this of the goal the crop snaps to it and holds still; an ease that never arrives
    /// would keep the shot drifting by a pixel forever.
    static let settle: CGFloat = 0.002
    static let minWidthFraction: CGFloat = 0.4
    static let outputAspect: CGFloat = 16.0 / 9.0
    /// Where the subject sits, from the top of the crop.
    static let subjectFromTop: CGFloat = 0.4

    public init() {}

    @discardableResult
    public mutating func step(subject: CGRect?, tightness: Double, sourceAspect: CGFloat, dt: TimeInterval) -> CGRect {
        // Normalized crop height per unit of normalized width, for a 16:9 crop in source pixels.
        let hPerW = sourceAspect / Self.outputAspect
        let maxW = min(1, 1 / hPerW)
        let target = Self.target(subject: subject, tightness: tightness, hPerW: hPerW, maxW: maxW)

        if let g = goal {
            let moved = abs(target.cx - g.cx) > Self.deadZoneCentre * g.w || abs(target.cy - g.cy) > Self.deadZoneCentre * g.w
            let resized = abs(target.w - g.w) > Self.deadZoneWidth * g.w
            if moved || resized { goal = target }
        } else {
            goal = target
        }
        let g = goal!
        var c = current ?? (cx: 0.5, cy: 0.5, w: maxW)
        let k = CGFloat(1 - pow(0.5, dt / Self.halfLife))
        c.cx += (g.cx - c.cx) * k
        c.cy += (g.cy - c.cy) * k
        c.w += (g.w - c.w) * k
        if abs(g.cx - c.cx) < Self.settle, abs(g.cy - c.cy) < Self.settle, abs(g.w - c.w) < Self.settle { c = g }
        current = c

        let w = c.w, h = c.w * hPerW
        crop = CGRect(x: c.cx - w / 2, y: c.cy - h / 2, width: w, height: h)
        return crop
    }

    /// The framing for this subject, clamped so its crop lies inside the source. Easing between
    /// two clamped framings stays inside too: every edge moves linearly between two in-bounds values.
    private static func target(subject: CGRect?, tightness: Double, hPerW: CGFloat, maxW: CGFloat) -> (cx: CGFloat, cy: CGFloat, w: CGFloat) {
        guard let s = subject else { return (0.5, 0.5, maxW) }
        let t = CGFloat(min(max(tightness, 0), 1))
        let w = min(max(s.width * (6 - 3 * t), minWidthFraction * maxW), maxW)
        let h = w * hPerW
        let cx = min(max(s.midX, w / 2), 1 - w / 2)
        let cy = min(max(s.midY + (0.5 - subjectFromTop) * h, h / 2), 1 - h / 2)
        return (cx, cy, w)
    }
}
