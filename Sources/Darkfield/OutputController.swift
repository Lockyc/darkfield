import AppKit
import DarkfieldCore

/// Shows the canvas where `Settings.output` says: for a meeting, the "▶ Darkfield" share window a
/// meeting app captures plus the presenter's preview; or full-screen on a projector display. One
/// output at a time.
///
/// A meeting app shares a window's pixels, so the share window is parked at the canvas's full
/// pixel size with all but one corner point off the displays, where the presenter never sees it.
/// It still counts as on screen, is offered by window pickers and streams every frame. The
/// presenter watches the preview, a small floating window that is not shareable.
@MainActor
final class OutputController {
    /// The share window's title, chosen to stand out in meeting apps' window pickers.
    static let meetingTitle = "▶ Darkfield"

    private let canvas: CanvasModel
    private var shareWindow: NSWindow?
    private var previewWindow: NSWindow?
    private var projectorWindow: NSWindow?
    private(set) var current: Output?
    /// Called when the projector disappears and output falls back to the meeting window.
    var onFallback: ((String) -> Void)?
    /// Called with whether the preview is on screen, whenever that changes.
    var onPreviewShown: ((Bool) -> Void)?
    /// Set while a window picker is open and the share window is shown for clicking; its
    /// expiry parks the window again if the picker's close is never announced.
    private var pickingExpiry: Timer?
    private let pickingOverlay = PickingOverlay()
    /// How long the share window stays shown for a picker whose close never arrives.
    private static let pickingTimeout: TimeInterval = 120

    /// Distributed notifications another app posts around a click-to-pick window picker (cooee
    /// posts them around Meet's). Any app may post them; they carry nothing.
    static let pickerWillOpen = Notification.Name("com.lockyc.darkfield.pickerWillOpen")
    static let pickerDidClose = Notification.Name("com.lockyc.darkfield.pickerDidClose")
    /// darkfield's answer to `pickerWillOpen`, once the share window is on screen (or there is
    /// nothing to show). A picker that lists windows as it opens must wait for it, or it opens
    /// with the window still parked.
    static let pickerReady = Notification.Name("com.lockyc.darkfield.pickerReady")

    init(canvas: CanvasModel) {
        self.canvas = canvas
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Self.pickerWillOpen, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showForPicking() }
            // The next turn of the run loop, once the window server has the move.
            DispatchQueue.main.async {
                DistributedNotificationCenter.default().postNotificationName(
                    Self.pickerReady, object: nil, userInfo: nil, deliverImmediately: true)
            }
        }
        center.addObserver(forName: Self.pickerDidClose, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.endPicking() }
        }
    }

    /// Shows the share window centred on the main display, in front of other windows, so a picker
    /// that selects by clicking can reach it. Meeting output only. While shown it stays at normal
    /// level, takes the mouse and drops `.stationary`: macOS's picker offers no window that is
    /// raised, that clicks pass through, or that is stationary.
    private func showForPicking() {
        guard current == .meeting, let w = shareWindow, let main = NSScreen.screens.first else { return }
        let primaryHeight = main.frame.height
        let display = CGRect(x: main.frame.minX, y: primaryHeight - main.frame.maxY,
                             width: main.frame.width, height: main.frame.height)
        let cg = Parking.pickingFrame(size: Layout.canvas, display: display)
        w.ignoresMouseEvents = false
        w.collectionBehavior.remove(.stationary)
        let frame = ScreenSpace.toAppKit(cg, primaryHeight: primaryHeight)
        w.setFrame(frame, display: true)
        w.orderFrontRegardless()
        if let content = w.contentView {
            pickingOverlay.frame = content.bounds
            content.addSubview(pickingOverlay)
        }
        pickingExpiry?.invalidate()
        pickingExpiry = Timer.scheduledTimer(withTimeInterval: Self.pickingTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.endPicking() }
        }
    }

    /// Parks the share window again; a capture already started keeps streaming it.
    private func endPicking() {
        guard pickingExpiry != nil else { return }
        pickingExpiry?.invalidate()
        pickingExpiry = nil
        pickingOverlay.removeFromSuperview()
        shareWindow?.ignoresMouseEvents = true
        shareWindow?.collectionBehavior.insert(.stationary)
        if current == .meeting { parkShare() }
    }

    func apply(_ output: Output) {
        switch output {
        case .meeting:
            closeProjector()
            current = .meeting
            showMeeting()
        case .projector(let id):
            guard let screen = Self.screen(for: id), CGDisplayIsInMirrorSet(id) == 0 else {
                fallBack(id)
                return
            }
            shareWindow?.orderOut(nil)
            previewWindow?.orderOut(nil)
            onPreviewShown?(false)
            showProjector(on: screen)
            current = output
        }
    }

    /// While projecting, the real cursor is kept off the projected canvas: a point that lands on the
    /// projector display is pushed back to the nearest point on any other display. (It can still
    /// show for a frame as it crosses — macOS has no per-display cursor hide.)
    func keepCursorOff(_ p: CGPoint) {
        guard case .projector(let id) = current, CGDisplayBounds(id).contains(p) else { return }
        let others = NSScreen.screens.compactMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }
            .filter { $0 != id }.map(CGDisplayBounds)
        let candidates = others.map { b in CGPoint(x: min(max(p.x, b.minX), b.maxX - 1), y: min(max(p.y, b.minY), b.maxY - 1)) }
        guard let back = candidates.min(by: { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) }) else { return }
        CGWarpMouseCursorPosition(back)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func showMeeting() {
        showShare()
        autoShowPreview()
    }

    private func showShare() {
        if shareWindow == nil {
            let w = ParkedWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            w.title = Self.meetingTitle
            w.backgroundColor = .black
            w.hasShadow = false
            w.ignoresMouseEvents = true
            // Normal level: Chromium's window picker lists only level-0 windows. On every Space,
            // so it streams whichever Space the presenter is on.
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.contentView = CanvasView(model: canvas)
            w.isReleasedWhenClosed = false
            shareWindow = w
        }
        parkShare()
        shareWindow?.orderFrontRegardless()
    }

    /// Sizes the share window to the canvas and parks it per `Parking`, so pickers can draw its
    /// thumbnail. It is the canvas size in points, which is at least one pixel per canvas point at
    /// any display scale.
    private func parkShare() {
        guard let w = shareWindow else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let displays = NSScreen.screens.map { f in
            CGRect(x: f.frame.minX, y: primaryHeight - f.frame.maxY, width: f.frame.width, height: f.frame.height)
        }
        let cg = Parking.frame(size: Layout.canvas, displays: displays)
        w.setFrame(ScreenSpace.toAppKit(cg, primaryHeight: primaryHeight), display: true)
    }

    /// Brings the preview back while presenting to a meeting; does nothing on a projector.
    func showPreviewIfMeeting() {
        if current == .meeting { showPreview() }
    }

    /// The preview opens by itself (on launch, on switching to Meeting, on sharing a window) only
    /// for the Meeting output with more than one display: on a lone screen it would sit over what
    /// is being presented, and a projector already shows the canvas.
    func autoShowPreview() {
        if NSScreen.screens.count > 1 { showPreviewIfMeeting() }
    }

    private func showPreview() {
        if previewWindow == nil {
            // The canvas fills the whole window, with only a close button over it. It is dragged
            // by its body and floats above the presenter's windows on every Space, including over
            // a full-screen presentation.
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "darkfield preview"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = true }
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onPreviewShown?(false) }
            }
            w.isMovableByWindowBackground = true
            w.level = .floating
            w.sharingType = .none
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.contentAspectRatio = Layout.canvas
            w.contentView = PreviewView(canvas: CanvasView(model: canvas)) { [weak w] in w?.performClose(nil) }
            w.isReleasedWhenClosed = false
            if let saved = Self.savedPreviewFrame() { w.setFrame(saved, display: false) } else { w.center() }
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { [weak w] _ in
                    MainActor.assumeIsolated { if let w { UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: Self.previewFrameKey) } }
                }
            }
            previewWindow = w
        }
        previewWindow?.orderFrontRegardless()
        onPreviewShown?(true)
    }

    private static let previewFrameKey = "PreviewWindowFrame"

    /// Where the presenter last left the preview, if that spot is still on a connected
    /// display. Kept by darkfield rather than AppKit's frame autosave, which restores a frame
    /// saved on a secondary display onto the main one.
    private static func savedPreviewFrame() -> NSRect? {
        guard let s = UserDefaults.standard.string(forKey: previewFrameKey) else { return nil }
        let r = NSRectFromString(s)
        guard r.width > 0, r.height > 0,
              NSScreen.screens.contains(where: { $0.frame.intersects(r) }) else { return nil }
        return r
    }

    private func showProjector(on screen: NSScreen) {
        closeProjector()
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        // Above every app window, the projector's own menu bar and alert windows: nothing but the
        // canvas may reach the wall.
        w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        w.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary, .ignoresCycle]
        w.backgroundColor = .black
        w.contentView = CanvasView(model: canvas)
        w.isReleasedWhenClosed = false
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        projectorWindow = w
    }

    private func closeProjector() {
        projectorWindow?.orderOut(nil)
        projectorWindow = nil
    }

    private func screensChanged() {
        if current == .meeting && pickingExpiry == nil { parkShare() }
        guard case .projector(let id) = current else { return }
        if let screen = Self.screen(for: id), CGDisplayIsInMirrorSet(id) == 0 {
            projectorWindow?.setFrame(screen.frame, display: true)
        } else {
            fallBack(id)
        }
    }

    private func fallBack(_ id: CGDirectDisplayID) {
        closeProjector()
        current = .meeting
        showMeeting()
        onFallback?(CGDisplayIsInMirrorSet(id) != 0 && Self.screen(for: id) != nil
            ? "Displays are mirrored — showing the Meeting window. Set them to extended to project."
            : "Projector disconnected — showing the Meeting window")
    }

    static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id }
    }
}

/// The preview's content: the canvas, with a close button over its top-left corner. The window's
/// own close button doesn't draw over the canvas, so the preview carries its own.
private final class PreviewView: NSView {
    private let onClose: () -> Void

    init(canvas: CanvasView, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(frame: .zero)
        canvas.autoresizingMask = [.width, .height]
        addSubview(canvas)
        let close = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close preview")!,
                             target: nil, action: nil)
        close.target = self
        close.action = #selector(closePressed)
        close.isBordered = false
        close.symbolConfiguration = .init(pointSize: 20, weight: .regular)
            .applying(.init(paletteColors: [.white, NSColor.black.withAlphaComponent(0.55)]))
        close.toolTip = "Close preview"
        close.translatesAutoresizingMaskIntoConstraints = false
        addSubview(close)
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            close.topAnchor.constraint(equalTo: topAnchor, constant: 8),
        ])
        canvas.frame = bounds
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func closePressed() { onClose() }
}

/// A window AppKit leaves where it is put, even off every display.
private final class ParkedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
