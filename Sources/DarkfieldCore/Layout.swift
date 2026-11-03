import CoreGraphics

/// How shared windows are arranged on the canvas.
public enum LayoutMode: String, Codable, Sendable {
    /// Arrange for the audience: a near-square grid in shared-set order, each window aspect-fit
    /// into its cell.
    case fill
    /// Keep the windows' real relative positions and sizes: their union is aspect-fit to the canvas.
    case mirror
}

public enum Layout {
    /// The canvas, in logical points. Canvas coordinates have a top-left origin, y down.
    public static let canvas = CGSize(width: 1920, height: 1080)

    /// Canvas rects for `sources` (the windows' current CG global frames, in shared-set order),
    /// one per source, in the same order. `margin` insets the canvas edge and separates grid cells.
    public static func frames(sources: [CGRect], mode: LayoutMode, margin: CGFloat, canvas: CGSize = canvas) -> [CGRect] {
        guard !sources.isEmpty else { return [] }
        let area = CGRect(origin: .zero, size: canvas).insetBy(dx: margin, dy: margin)
        switch mode {
        case .fill:
            let n = sources.count
            let cols = Int(Double(n).squareRoot().rounded(.up))
            let rows = (n + cols - 1) / cols
            let cellW = (area.width - CGFloat(cols - 1) * margin) / CGFloat(cols)
            let cellH = (area.height - CGFloat(rows - 1) * margin) / CGFloat(rows)
            return sources.enumerated().map { i, src in
                let cell = CGRect(x: area.minX + CGFloat(i % cols) * (cellW + margin),
                                  y: area.minY + CGFloat(i / cols) * (cellH + margin),
                                  width: cellW, height: cellH)
                return aspectFit(src.size, in: cell)
            }
        case .mirror:
            let union = sources.dropFirst().reduce(sources[0]) { $0.union($1) }
            let fitted = aspectFit(union.size, in: area)
            let scale = fitted.width / union.width
            return sources.map { src in
                CGRect(x: fitted.minX + (src.minX - union.minX) * scale,
                       y: fitted.minY + (src.minY - union.minY) * scale,
                       width: src.width * scale, height: src.height * scale)
            }
        }
    }

    /// The largest rect with `size`'s aspect ratio that fits `box`, centred in it.
    static func aspectFit(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(x: box.midX, y: box.midY, width: 0, height: 0) }
        let scale = min(box.width / size.width, box.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }
}
