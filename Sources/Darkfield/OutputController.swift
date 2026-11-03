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
                fallBack()
                return
            }
            meetingWindow?.orderOut(nil)
            showProjector(on: screen)
            current = output
        }
    }

    /// While projecting, the real cursor must never appear on the projected canvas: a point that
    /// lands on the projector display is pushed back to the nearest point on the menu-bar display.
    func keepCursorOff(_ p: CGPoint) {
        guard case .projector(let id) = current else { return }
        let projector = CGDisplayBounds(id)
        guard projector.contains(p) else { return }
        let main = CGDisplayBounds(CGMainDisplayID())
        let back = CGPoint(x: min(max(p.x, main.minX), main.maxX - 1), y: min(max(p.y, main.minY), main.maxY - 1))
        CGWarpMouseCursorPosition(back)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func showMeeting() {
        if meetingWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
                             styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            w.title = Self.meetingTitle
            w.contentAspectRatio = Layout.canvas
            w.contentView = CanvasView(model: canvas)
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("MeetingWindow")
            if !w.setFrameUsingName("MeetingWindow") { w.center() }
            meetingWindow = w
        }
        meetingWindow?.orderFrontRegardless()
    }

    private func showProjector(on screen: NSScreen) {
        closeProjector()
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        w.level = .normal
        w.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
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
            fallBack()
        }
    }

    private func fallBack() {
        closeProjector()
        showMeeting()
        current = .meeting
        onFallback?("Projector disconnected — showing the Meeting window")
    }

    static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id }
    }
}
