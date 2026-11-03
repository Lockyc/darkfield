import AppKit
import DarkfieldCore
import QuartzCore

/// One drawing of the canvas: fixed 1920×1080 bounds in canvas coordinates (top-left origin), the
/// wallpaper, each shared window's latest frame, the audience pointer and click ripples. Hosts scale
/// it to fit with `CanvasView`. Several instances can render one `CanvasModel`.
final class CanvasLayer: CALayer {
    private let background = CALayer()
    private var tileLayers: [CGWindowID: CALayer] = [:]
    private let pointerOuter = CAShapeLayer()
    private let pointerInner = CAShapeLayer()
    private var rippleLayers: [CAShapeLayer] = []

    static let leftRipple = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.25, alpha: 1).cgColor
    static let rightRipple = NSColor(calibratedRed: 0.35, green: 0.75, blue: 1.0, alpha: 1).cgColor

    override init() {
        super.init()
        isGeometryFlipped = true
        bounds = CGRect(origin: .zero, size: Layout.canvas)
        masksToBounds = true
        backgroundColor = NSColor.black.cgColor
        background.frame = bounds
        background.contentsGravity = .resizeAspectFill
        addSublayer(background)
        for (layer, color, width) in [(pointerOuter, NSColor.black.withAlphaComponent(0.75), 9.0),
                                      (pointerInner, NSColor.white, 4.0)] {
            layer.fillColor = nil
            layer.strokeColor = color.cgColor
            layer.lineWidth = width
            layer.zPosition = 10
            addSublayer(layer)
        }
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    @MainActor func render(_ m: CanvasModel) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        background.contents = m.backgroundSurface ?? m.backgroundImage

        let ids = Set(m.tiles.map(\.id))
        for (id, layer) in tileLayers where !ids.contains(id) {
            layer.removeFromSuperlayer()
            tileLayers[id] = nil
        }
        for (i, tile) in m.tiles.enumerated() {
            let layer = tileLayers[tile.id] ?? {
                let l = CALayer()
                l.contentsGravity = .resizeAspect
                l.shadowOpacity = 0.35
                l.shadowRadius = 18
                l.shadowOffset = CGSize(width: 0, height: 6)
                addSublayer(l)
                tileLayers[tile.id] = l
                return l
            }()
            layer.frame = tile.canvasFrame
            layer.zPosition = CGFloat(i)
            layer.contents = tile.surface
        }

        let radius = PointerState.radius(canvasHeight: bounds.height) * m.pointerScale
        if let p = m.pointer, m.pointerOpacity > 0 {
            let path = CGPath(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2), transform: nil)
            for l in [pointerOuter, pointerInner] {
                l.path = path
                l.opacity = Float(m.pointerOpacity)
                l.isHidden = false
            }
        } else {
            pointerOuter.isHidden = true
            pointerInner.isHidden = true
        }

        renderRipples(m.ripples, now: CACurrentMediaTime())
    }

    private func renderRipples(_ ripples: [Ripple], now: CFTimeInterval) {
        while rippleLayers.count < ripples.count {
            let l = CAShapeLayer()
            l.fillColor = nil
            l.lineWidth = 5
            l.zPosition = 9
            addSublayer(l)
            rippleLayers.append(l)
        }
        let base = PointerState.radius(canvasHeight: bounds.height)
        for (i, l) in rippleLayers.enumerated() {
            guard i < ripples.count else { l.isHidden = true; continue }
            let r = ripples[i]
            let progress = min(1, max(0, (now - r.start) / Ripple.duration))
            let radius = base * (1 + 2.5 * progress)
            l.path = CGPath(ellipseIn: CGRect(x: r.at.x - radius, y: r.at.y - radius, width: radius * 2, height: radius * 2), transform: nil)
            l.strokeColor = r.kind == .left ? Self.leftRipple : Self.rightRipple
            l.opacity = Float(1 - progress)
            l.isHidden = false
        }
    }
}

/// An NSView that hosts a `CanvasLayer`, aspect-fit and centred.
final class CanvasView: NSView {
    let canvas = CanvasLayer()

    init(model: CanvasModel) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(canvas)
        model.register(canvas)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = min(bounds.width / Layout.canvas.width, bounds.height / Layout.canvas.height)
        canvas.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        canvas.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }
}
