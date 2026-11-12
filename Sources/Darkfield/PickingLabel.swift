import AppKit

/// The label above the share window while it is shown for a window picker: which window to pick.
/// Its own window, never the canvas, so nothing the presenter didn't pick reaches a share; it is
/// unshareable and clicks pass through it, so pickers neither offer nor hit it.
@MainActor
final class PickingLabel {
    private var window: NSWindow?
    private static let gap: CGFloat = 16

    /// Shows the label centred above `canvas` (AppKit points), or below it when there is no room
    /// above on `screen`.
    func show(over canvas: NSRect, on screen: NSScreen) {
        let w = window ?? make()
        window = w
        let size = w.contentView?.fittingSize ?? NSSize(width: 600, height: 80)
        var origin = NSPoint(x: canvas.midX - size.width / 2, y: canvas.maxY + Self.gap)
        if origin.y + size.height > screen.visibleFrame.maxY {
            origin.y = canvas.minY - Self.gap - size.height
        }
        w.setFrame(NSRect(origin: origin, size: size), display: true)
        w.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func make() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.ignoresMouseEvents = true
        w.sharingType = .none
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        w.isReleasedWhenClosed = false

        let title = NSTextField(labelWithString: "Share this window: \(OutputController.meetingTitle)")
        title.font = .systemFont(ofSize: 34, weight: .bold)
        title.textColor = .white
        let hint = NSTextField(labelWithString: "Point at it and click Share")
        hint.font = .systemFont(ofSize: 20, weight: .medium)
        hint.textColor = NSColor.white.withAlphaComponent(0.8)
        let stack = NSStackView(views: [title, hint])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 32, bottom: 18, right: 32)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.95).cgColor
        stack.layer?.cornerRadius = 16
        w.contentView = stack
        return w
    }
}
