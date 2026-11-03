import CoreGraphics
import Foundation

public enum Click: Sendable { case left, right }

/// A click ring expanding from `at` (canvas point) for `duration` seconds from `start`.
public struct Ripple: Equatable, Sendable {
    public let at: CGPoint
    public let kind: Click
    public let start: TimeInterval
    public static let duration: TimeInterval = 0.4

    public init(at: CGPoint, kind: Click, start: TimeInterval) {
        self.at = at
        self.kind = kind
        self.start = start
    }
}

/// The audience pointer's timing: idle fade and shake-to-spotlight. Fed every real mouse move.
public struct PointerState: Sendable {
    static let fadeDuration: TimeInterval = 0.5
    static let spotlightDuration: TimeInterval = 0.8
    static let spotlightScale = 3.0
    /// A shake is `shakeReversals` horizontal reversals within `shakeWindow`, each after at least
    /// `shakeTravel` points of travel the other way.
    static let shakeWindow: TimeInterval = 0.6
    static let shakeReversals = 4
    static let shakeTravel: CGFloat = 30

    private var lastMove: TimeInterval?
    private var lastX: CGFloat?
    private var direction: CGFloat = 0
    private var travel: CGFloat = 0
    private var reversals: [TimeInterval] = []
    private var shakeAt: TimeInterval?

    public init() {}

    public mutating func moved(to p: CGPoint, at t: TimeInterval) {
        lastMove = t
        defer { lastX = p.x }
        guard let lastX else { return }
        let dx = p.x - lastX
        guard dx != 0 else { return }
        let dir: CGFloat = dx > 0 ? 1 : -1
        if dir == direction {
            travel += abs(dx)
            return
        }
        if direction != 0, travel >= Self.shakeTravel {
            reversals.append(t)
            reversals.removeAll { t - $0 > Self.shakeWindow }
            if reversals.count >= Self.shakeReversals {
                shakeAt = t
                reversals.removeAll()
            }
        }
        direction = dir
        travel = abs(dx)
    }

    /// 1 until `idleFade` seconds after the last move, then a linear fade to 0 over half a second.
    /// nil `idleFade` = always 1. Before any move the pointer is hidden unless it never fades.
    public func opacity(at t: TimeInterval, idleFade: TimeInterval?) -> Double {
        guard let idleFade else { return 1 }
        guard let lastMove else { return 0 }
        let over = t - lastMove - idleFade
        if over <= 0 { return 1 }
        return max(0, 1 - over / Self.fadeDuration)
    }

    public func spotlightScale(at t: TimeInterval) -> Double {
        guard let shakeAt, t >= shakeAt, t - shakeAt <= Self.spotlightDuration else { return 1 }
        return Self.spotlightScale
    }

    /// The pointer ring's radius, relative to the canvas so it stays legible when scaled up.
    public static func radius(canvasHeight: CGFloat) -> CGFloat { canvasHeight * 0.018 }
}
