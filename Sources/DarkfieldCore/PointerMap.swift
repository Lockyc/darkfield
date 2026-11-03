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

public enum PointerMap {
    /// The canvas point under the real mouse at `p` (CG global), or nil when `p` is over no shared
    /// window. Where shared windows overlap on screen, the one first in `zOrder` (front-to-back) wins.
    public static func canvasPoint(_ p: CGPoint, placed: [PlacedWindow], zOrder: [CGWindowID]) -> CGPoint? {
        for id in zOrder {
            guard let w = placed.first(where: { $0.id == id }), w.screenFrame.contains(p),
                  w.screenFrame.width > 0, w.screenFrame.height > 0 else { continue }
            let u = (p.x - w.screenFrame.minX) / w.screenFrame.width
            let v = (p.y - w.screenFrame.minY) / w.screenFrame.height
            return CGPoint(x: w.canvasFrame.minX + u * w.canvasFrame.width,
                           y: w.canvasFrame.minY + v * w.canvasFrame.height)
        }
        return nil
    }
}
