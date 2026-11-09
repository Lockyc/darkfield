import AppKit
import DarkfieldCore

/// What the presenter sees and hears when the hotkey shares or unshares a window: a ring flashed
/// around the window and a sound. Shared rings in the app icon's amber, unshared in grey.
@MainActor
enum ToggleFeedback {
    private static var flashes: Set<NSWindow> = []

    /// `frame` is the window's CG global frame.
    static func show(_ result: ToggleResult, frame: CGRect) {
        switch result {
        case .added:
            NSSound(named: "Tink")?.play()
            flash(frame, color: NSColor(calibratedRed: 0.96, green: 0.73, blue: 0.26, alpha: 1))
        case .removed:
            NSSound(named: "Pop")?.play()
            flash(frame, color: NSColor(white: 0.6, alpha: 1))
        case .refusedOwnWindow:
            NSSound.beep()
        }
    }

    private static func flash(_ cgFrame: CGRect, color: NSColor) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frame = ScreenSpace.toAppKit(cgFrame, primaryHeight: primaryHeight).insetBy(dx: -6, dy: -6)
        let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .statusBar
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let ring = NSView(frame: NSRect(origin: .zero, size: frame.size))
        ring.wantsLayer = true
        ring.layer?.borderWidth = 6
        ring.layer?.cornerRadius = 14
        ring.layer?.borderColor = color.cgColor
        w.contentView = ring
        w.orderFrontRegardless()
        flashes.insert(w)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.45
                w.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    w.orderOut(nil)
                    flashes.remove(w)
                }
            })
        }
    }
}
