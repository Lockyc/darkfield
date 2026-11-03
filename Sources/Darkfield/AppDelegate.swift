import AppKit
import DarkfieldCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let windowToggleID: UInt32 = 1
    static let pointerToggleID: UInt32 = 2

    let model = CanvasModel()
    lazy var captures = CaptureManager(model: model)
    private let hotKeys = HotKeys()
    private let pointerInput = PointerInput()
    private var pointerState = PointerState()
    private var tick: Timer?
    private var statusItem: NSStatusItem?
    private var debugWindow: NSWindow?

    var settings = Settings() {
        didSet {
            captures.settings = settings
            settings.save(to: .standard)
            if oldValue.windowHotKey != settings.windowHotKey { hotKeys.set(settings.windowHotKey, id: Self.windowToggleID) }
            if oldValue.pointerHotKey != settings.pointerHotKey { hotKeys.set(settings.pointerHotKey, id: Self.pointerToggleID) }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        settings = Settings.load(from: .standard)
        hotKeys.set(settings.windowHotKey, id: Self.windowToggleID)
        hotKeys.set(settings.pointerHotKey, id: Self.pointerToggleID)
        hotKeys.onPress = { [weak self] id in self?.hotKey(id) }
        captures.start()
        startPointer()

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
        menu.addItem(withTitle: "Quit darkfield", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func hotKey(_ id: UInt32) {
        switch id {
        case Self.windowToggleID:
            guard let app = NSWorkspace.shared.frontmostApplication else { return }
            Task { await captures.toggleFrontWindow(of: app) }
        case Self.pointerToggleID:
            settings.pointerEnabled.toggle()
        default:
            break
        }
    }

    private func startPointer() {
        pointerInput.start(onMove: { [weak self] p in
            guard let self else { return }
            pointerState.moved(to: p, at: CACurrentMediaTime())
            model.pointer = PointerMap.canvasPoint(p, placed: model.placed, zOrder: captures.zOrder)
        }, onClick: { [weak self] kind, p in
            guard let self, settings.pointerEnabled,
                  let at = PointerMap.canvasPoint(p, placed: model.placed, zOrder: captures.zOrder) else { return }
            model.ripples.append(Ripple(at: at, kind: kind, start: CACurrentMediaTime()))
        })
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    /// Advances fade, spotlight and ripples; redraws only while something is visible or changing.
    private func tickPointer() {
        let now = CACurrentMediaTime()
        let opacity = settings.pointerEnabled ? pointerState.opacity(at: now, idleFade: settings.idleFade) : 0
        let scale = pointerState.spotlightScale(at: now)
        let ripples = model.ripples.filter { now - $0.start < Ripple.duration }
        let animating = !ripples.isEmpty || !model.ripples.isEmpty || (model.pointer != nil && opacity > 0)
        guard animating || opacity != model.pointerOpacity || scale != model.pointerScale else { return }
        model.pointerOpacity = opacity
        model.pointerScale = scale
        model.ripples = ripples
        model.changed()
    }
}
