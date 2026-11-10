import AppKit
import DarkfieldCore

/// An amber ring around every shared window on the presenter's screen, for as long as it is
/// shared. Each ring is its own click-through window at the floating level, above normal windows,
/// so a window brought in front of the shared one still shows its ring. The level keeps the rings
/// out of meeting apps' window pickers: Chromium's lists only level-0 windows, and a ring offered
/// there shares as black. Rings follow their windows ten times a second, hide while the window is
/// off screen, and fade out on unshare.
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
        var onScreen: [CGWindowID: CGRect] = [:]
        for w in list {
            if let id = w[kCGWindowNumber as String] as? CGWindowID, ids.contains(id),
               let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b) {
                onScreen[id] = r
            }
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for id in ids {
            let ring = rings[id] ?? makeRing(for: id)
            guard let cg = onScreen[id] else {
                ring.orderOut(nil)
                continue
            }
            let frame = ScreenSpace.toAppKit(cg, primaryHeight: primaryHeight).insetBy(dx: -Self.width, dy: -Self.width)
            if ring.frame != frame { ring.setFrame(frame, display: true) }
            if !ring.isVisible { ring.orderFrontRegardless() }
        }
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
