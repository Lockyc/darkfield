import AppKit
import DarkfieldCore

/// Observes the real mouse everywhere — moves, drags and clicks — and reports CG global points.
/// Global monitors for mouse events need no Accessibility grant; the local monitor covers
/// darkfield's own windows, which global monitors skip.
@MainActor
final class PointerInput {
    private var monitors: [Any] = []

    func start(onMove: @escaping (CGPoint) -> Void, onClick: @escaping (Click, CGPoint) -> Void) {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown]
        let handle: (NSEvent) -> Void = { event in
            let p = ScreenSpace.toCG(NSEvent.mouseLocation, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
            switch event.type {
            case .leftMouseDown: onClick(.left, p)
            case .rightMouseDown: onClick(.right, p)
            default: onMove(p)
            }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { e in MainActor.assumeIsolated { handle(e) } }) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { e in handle(e); return e }) {
            monitors.append(l)
        }
    }
}
