import AppKit
import DarkfieldCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = CanvasModel()
    lazy var captures = CaptureManager(model: model)
    private var statusItem: NSStatusItem?
    private var debugWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        captures.settings = Settings.load(from: .standard)
        captures.start()

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
                              styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.title = "darkfield debug"
        window.contentView = CanvasView(model: model)
        window.center()
        window.orderFrontRegardless()
        debugWindow = window

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "darkfield")
        let menu = NSMenu()
        menu.addItem(withTitle: "Share Frontmost Window", action: #selector(shareFrontmost), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit darkfield", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        // Temporary debug hook until the hotkey lands: `-DarkfieldDebugShare 123,456` shares windows by id.
        if let ids = UserDefaults.standard.string(forKey: "DarkfieldDebugShare") {
            for id in ids.split(separator: ",").compactMap({ CGWindowID($0) }) { captures.toggle(id, ownerPID: -1) }
        }
    }

    @objc private func shareFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        Task { await captures.toggleFrontWindow(of: app) }
    }
}
