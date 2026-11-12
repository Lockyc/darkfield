import AppKit
import SwiftUI

/// The menu-bar item: a click opens the control panel beneath it.
@MainActor
final class StatusItem: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    /// True when the panel opens, false when it closes however it closes.
    var onPanel: ((Bool) -> Void)?

    init(model: AppModel, openSettings: @escaping () -> Void) {
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        let panel = NSHostingController(rootView: PanelView(model: model, openSettings: { [weak self] in
            self?.popover.performClose(nil)
            openSettings()
        }))
        // The popover anchors itself to its content size. Left at its default size, it places the
        // panel for 320×320, then the taller SwiftUI view grows the window up past the screen top.
        panel.sizingOptions = .preferredContentSize
        popover.contentViewController = panel
        item.button?.image = Self.menuBarImage()
        item.button?.target = self
        item.button?.action = #selector(toggle)
    }

    /// The app icon's mark (`Support/icon.svg`) as a menu-bar template: the shared-window card with
    /// its title band and the audience-pointer ring, cut out of a solid card.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { _ in
            let card = NSRect(x: 1, y: 2, width: 18, height: 12)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: card, xRadius: 1.6, yRadius: 1.6).fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(rect: NSRect(x: card.minX, y: card.minY + 2.4, width: card.width, height: 1)).fill()
            let ring = NSBezierPath(ovalIn: NSRect(x: card.midX - 2.2, y: card.minY + 6.4 - 2.2, width: 4.4, height: 4.4))
            ring.lineWidth = 1.4
            ring.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "darkfield"
        return image
    }

    /// Closes the panel on a click in another app. `.transient` alone stops doing this once a
    /// picker's menu has been open: darkfield is an accessory app that never activates, and after
    /// the menu's tracking session the popover no longer sees outside clicks.
    private var outsideClicks: Any?

    func popoverWillShow(_ notification: Notification) {
        CameraController.log.info("panel will show")
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }
        onPanel?(true)
    }

    func popoverDidClose(_ notification: Notification) {
        CameraController.log.info("panel did close")
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
        onPanel?(false)
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
