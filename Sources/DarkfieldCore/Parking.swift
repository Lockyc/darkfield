import CoreGraphics

/// Where the share window is parked: off the presenter's view, but with exactly one point on a
/// display. A window entirely off every display streams, but a one-off `SCScreenshotManager`
/// capture of it fails with `-3811`, and that capture is what meeting apps' window pickers draw
/// their thumbnails from. One point on screen is enough for the whole window to capture.
public enum Parking {
    /// The parked frame for a window of `size`, in CG global coordinates. Its top-left point
    /// covers the bottom-right point of the first display where no other display is touched;
    /// with no such display, it sits wholly beyond the bottom-right of them all.
    public static func frame(size: CGSize, displays: [CGRect]) -> CGRect {
        for d in displays {
            let r = CGRect(origin: CGPoint(x: d.maxX - 1, y: d.maxY - 1), size: size)
            let covered = displays.reduce(CGFloat(0)) { sum, o in
                let i = o.intersection(r)
                return sum + (i.isNull ? 0 : i.width * i.height)
            }
            if covered == 1 { return r }
        }
        let all = displays.reduce(CGRect.null) { $0.union($1) }
        return CGRect(origin: CGPoint(x: all.maxX, y: all.maxY), size: size)
    }
}
