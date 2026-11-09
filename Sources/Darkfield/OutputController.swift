import AppKit
import DarkfieldCore

/// Shows the canvas where `Settings.output` says: the "▶ Darkfield" window a meeting app shares, or
/// full-screen on a projector display. One output at a time.
@MainActor
final class OutputController {
    /// The share target's title, chosen to stand out in meeting apps' window pickers.
    static let meetingTitle = "▶ Darkfield"

    private let canvas: CanvasModel
    private var meetingWindow: NSWindow?
    private var projectorWindow: NSWindow?
    private(set) var current: Output?
    /// Called when the projector disappears and output falls back to the meeting window.
    var onFallback: ((String) -> Void)?

    init(canvas: CanvasModel) {
        self.canvas = canvas
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    func apply(_ output: Output) {
        switch output {
        case .meeting:
            closeProjector()
            showMeeting()
            current = .meeting
        case .projector(let id):
            guard let screen = Self.screen(for: id), CGDisplayIsInMirrorSet(id) == 0 else {
                fallBack(id)
                return
            }
            meetingWindow?.orderOut(nil)
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
        if meetingWindow == nil {
            // The canvas fills the whole window, with no title text or buttons, so a meeting app
            // sharing it shows the canvas alone. It is dragged by its body. The title stays, for
            // meeting apps' window pickers.
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
                             styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = Self.meetingTitle
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = true }
            w.isMovableByWindowBackground = true
            // Stays above the presenter's windows, on every Space, including over a full-screen
            // presentation.
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.contentAspectRatio = Layout.canvas
            w.contentView = CanvasView(model: canvas)
            w.isReleasedWhenClosed = false
            if let saved = Self.savedMeetingFrame() { w.setFrame(saved, display: false) } else { w.center() }
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { [weak w] _ in
                    MainActor.assumeIsolated { if let w { UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: Self.meetingFrameKey) } }
                }
            }
            meetingWindow = w
        }
        meetingWindow?.orderFrontRegardless()
    }

    private static let meetingFrameKey = "MeetingWindowFrame"

    /// Where the presenter last left the Meeting window, if that spot is still on a connected
    /// display. Kept by darkfield rather than AppKit's frame autosave, which restores a frame
    /// saved on a secondary display onto the main one.
    private static func savedMeetingFrame() -> NSRect? {
        guard let s = UserDefaults.standard.string(forKey: meetingFrameKey) else { return nil }
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
        guard case .projector(let id) = current else { return }
        if let screen = Self.screen(for: id), CGDisplayIsInMirrorSet(id) == 0 {
            projectorWindow?.setFrame(screen.frame, display: true)
        } else {
            fallBack(id)
        }
    }

    private func fallBack(_ id: CGDirectDisplayID) {
        closeProjector()
        showMeeting()
        current = .meeting
        onFallback?(CGDisplayIsInMirrorSet(id) != 0 && Self.screen(for: id) != nil
            ? "Displays are mirrored — showing the Meeting window. Set them to extended to project."
            : "Projector disconnected — showing the Meeting window")
    }

    static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id }
    }
}
