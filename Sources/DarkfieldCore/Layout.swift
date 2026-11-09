import CoreGraphics

/// The canvas is a stack: every shared window is aspect-fit to the canvas (inside the margin) on
/// its own, and they are layered in their on-screen stacking order, so the window the presenter
/// brings forward is the one the audience sees.
public enum Layout {
    /// The canvas, in logical points. Canvas coordinates have a top-left origin, y down.
    public static let canvas = CGSize(width: 1920, height: 1080)

    /// Canvas rects for `sources` (the windows' current CG global frames), one per source, in the
    /// same order. `margin` insets the canvas edge.
    public static func frames(sources: [CGRect], margin: CGFloat, canvas: CGSize = canvas) -> [CGRect] {
        let area = CGRect(origin: .zero, size: canvas).insetBy(dx: margin, dy: margin)
        return sources.map { aspectFit($0.size, in: area) }
    }

    /// `ids` (shared-set order) ordered back to front for the canvas. Windows in `frontToBack` (the
    /// on-screen stacking) follow it; windows not on screen, such as one on another Space, go to the
    /// back in shared-set order.
    public static func backToFront(_ ids: [CGWindowID], frontToBack: [CGWindowID]) -> [CGWindowID] {
        let rank = Dictionary(frontToBack.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let off = ids.filter { rank[$0] == nil }
        let on = ids.filter { rank[$0] != nil }.sorted { rank[$0]! > rank[$1]! }
        return off + on
    }

    /// The largest rect with `size`'s aspect ratio that fits `box`, centred in it.
    static func aspectFit(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(x: box.midX, y: box.midY, width: 0, height: 0) }
        let scale = min(box.width / size.width, box.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }
}
