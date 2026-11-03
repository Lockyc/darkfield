import AppKit
import SwiftUI

/// The menu-bar item: a click opens the control panel beneath it.
@MainActor
final class StatusItem: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()

    init(model: AppModel, openSettings: @escaping () -> Void) {
        super.init()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model, openSettings: { [weak self] in
            self?.popover.performClose(nil)
            openSettings()
        }))
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "darkfield")
        item.button?.target = self
        item.button?.action = #selector(toggle)
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
