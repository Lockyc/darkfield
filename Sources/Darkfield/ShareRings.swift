import AppKit
import DarkfieldCore

/// An amber ring around every shared window on the presenter's screen, for as long as it is
/// shared. Each ring is its own click-through window at the floating level, which keeps it out of
/// meeting apps' window pickers: Chromium's lists only level-0 windows, and a ring offered there
/// shares as black. Above normal windows, a ring is cut away wherever a window in front of its
/// shared window overlaps it (`RingCover`), so it looks as if it sat directly above its window.
/// Rings follow their windows ten times a second, hide while the window is off screen, and fade
/// out on unshare.
@MainActor
final class ShareRings {
    static let color = NSColor(calibratedRed: 0.96, green: 0.73, blue: 0.26, alpha: 1)
    static let width: CGFloat = 4

    private var rings: [CGWindowID: NSWindow] = [:]
    private var timer: Timer?
    private let sharedIDs: () -> [CGWindowID]

    init(sharedIDs: @escaping () -> [CGWindowID]) {
        self.sharedIDs = sharedIDs
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The rings' own window numbers.
    var windowIDs: Set<CGWindowID> { Set(rings.values.map { CGWindowID($0.windowNumber) }) }

    func update() {
        let ids = sharedIDs()
        for (id, ring) in rings where !ids.contains(id) {
            rings[id] = nil
            fadeOut(ring)
        }
        guard !ids.isEmpty else { return }
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let stack: [OnScreenWindow] = list.compactMap { w in
            guard (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b) else { return nil }
            return OnScreenWindow(id: id, frame: r)
        }
        let own = windowIDs
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for id in ids {
            let ring = rings[id] ?? makeRing(for: id)
            guard let cg = stack.first(where: { $0.id == id })?.frame else {
                ring.orderOut(nil)
                continue
            }
            let ringCG = cg.insetBy(dx: -Self.width, dy: -Self.width)
            let frame = ScreenSpace.toAppKit(ringCG, primaryHeight: primaryHeight)
            if ring.frame != frame { ring.setFrame(frame, display: true) }
            mask(ring, cutting: RingCover.covers(ring: ringCG, shared: id, stack: stack, ignoring: own))
            if !ring.isVisible { ring.orderFrontRegardless() }
        }
    }

    /// Hides the parts of `ring` under `covers` (ring-local, y up).
    private func mask(_ ring: NSWindow, cutting covers: [CGRect]) {
        guard let layer = ring.contentView?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if covers.isEmpty {
            layer.mask = nil
        } else {
            let shape = (layer.mask as? CAShapeLayer) ?? CAShapeLayer()
            shape.frame = layer.bounds
            let hidden = covers.reduce(CGMutablePath()) { $0.addRect($1); return $0 }
            shape.path = CGPath(rect: layer.bounds, transform: nil).subtracting(hidden)
            layer.mask = shape
        }
        CATransaction.commit()
    }

    private func makeRing(for id: CGWindowID) -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .floating
        // Not a share target, for pickers that honour the sharing state.
        w.sharingType = .none
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.borderWidth = Self.width
        view.layer?.cornerRadius = 14
        view.layer?.borderColor = Self.color.cgColor
        view.autoresizingMask = [.width, .height]
        w.contentView = view
        rings[id] = w
        return w
    }

    private func fadeOut(_ ring: NSWindow) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ring.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { ring.orderOut(nil) }
        })
    }
}
