import CoreGraphics

/// A shared window as laid out: where it is on screen and where it lands on the canvas.
public struct PlacedWindow: Equatable, Sendable {
    public let id: CGWindowID
    public let screenFrame: CGRect
    public let canvasFrame: CGRect

    public init(id: CGWindowID, screenFrame: CGRect, canvasFrame: CGRect) {
        self.id = id
        self.screenFrame = screenFrame
        self.canvasFrame = canvasFrame
    }
}

/// Any window on screen, shared or not, with its CG global frame.
public struct OnScreenWindow: Equatable, Sendable {
    public let id: CGWindowID
    public let frame: CGRect

    public init(id: CGWindowID, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

public enum PointerMap {
    /// Whether a window can stand between the mouse and a shared window: a visible window below the
    /// Dock's level. System layers from the Dock up include full-display transparent overlays
    /// (Notification Centre's covers every display) that would otherwise hide the pointer
    /// everywhere.
    public static func canHidePointer(layer: Int, alpha: Double) -> Bool {
        alpha > 0 && layer < Int(CGWindowLevelForKey(.dockWindow))
    }

    /// The canvas point under the real mouse at `p` (CG global), or nil when the topmost window
    /// under `p` is not shared — a meeting app's floating toolbar over a shared slide hides the
    /// audience pointer. `onScreen` is every on-screen window, front to back.
    public static func canvasPoint(_ p: CGPoint, placed: [PlacedWindow], onScreen: [OnScreenWindow]) -> CGPoint? {
        guard let top = onScreen.first(where: { $0.frame.contains(p) }),
              let w = placed.first(where: { $0.id == top.id }),
              w.screenFrame.width > 0, w.screenFrame.height > 0 else { return nil }
        let u = (p.x - w.screenFrame.minX) / w.screenFrame.width
        let v = (p.y - w.screenFrame.minY) / w.screenFrame.height
        return CGPoint(x: w.canvasFrame.minX + u * w.canvasFrame.width,
                       y: w.canvasFrame.minY + v * w.canvasFrame.height)
    }
}
