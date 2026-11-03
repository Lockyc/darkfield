import CoreGraphics

/// Conversion between AppKit global points (origin bottom-left of the primary display, y up) and
/// CG global coordinates (origin top-left of the primary display, y down), which Core uses throughout.
public enum ScreenSpace {
    public static func toCG(_ p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}
