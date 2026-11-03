import AppKit
import DarkfieldCore
import ScreenCaptureKit

/// Keeps one `WindowCapture` per shared window and the wallpaper capture in step with the shared
/// set and the system's windows, polling `SCShareableContent` twice a second, and lays the result
/// out into the `CanvasModel`.
@MainActor
final class CaptureManager {
    private(set) var set = SharedSet()
    private(set) var availability: [CGWindowID: Availability] = [:]
    /// Shared windows' titles and owning apps, for the panel.
    private(set) var info: [CGWindowID: (title: String, app: NSRunningApplication?)] = [:]
    /// Every on-screen window, front to back, for pointer hit-testing.
    private(set) var onScreen: [OnScreenWindow] = []
    var settings = Settings() { didSet { relayout() } }
    var onChange: (() -> Void)?

    private let model: CanvasModel
    private let wallpaper = Wallpaper()
    private var captures: [CGWindowID: WindowCapture] = [:]
    private var surfaces: [CGWindowID: IOSurface] = [:]
    private var suspended: Set<CGWindowID> = []
    private var frames: [CGWindowID: CGRect] = [:]
    private var timer: Timer?
    private var polling = false

    init(model: CanvasModel) {
        self.model = model
        wallpaper.onChange = { [weak self] in
            guard let self else { return }
            self.model.backgroundSurface = self.wallpaper.surface
            self.model.backgroundImage = self.wallpaper.image
            self.model.changed()
        }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        Task { await poll() }
    }

    /// Toggles the frontmost window of `app` in or out of the shared set.
    func toggleFrontWindow(of app: NSRunningApplication) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return }
        let order = Dictionary(uniqueKeysWithValues: Self.onScreenWindows().enumerated().map { ($1.id, $0) })
        let candidates = content.windows.filter { $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 }
        guard let window = candidates.min(by: { (order[$0.windowID] ?? .max) < (order[$1.windowID] ?? .max) }) else { return }
        toggle(window.windowID, ownerPID: app.processIdentifier)
    }

    /// Windows that can be shared from the panel: on-screen, normal-layer, not darkfield's own.
    func shareableWindows() async -> [SCWindow] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        return content.windows.filter {
            $0.windowLayer == 0 && $0.owningApplication != nil && $0.owningApplication?.processID != me
                && $0.frame.width > 80 && $0.frame.height > 60 && !set.ids.contains($0.windowID)
        }
    }

    func toggle(_ id: CGWindowID, ownerPID: pid_t) {
        if set.toggle(id, ownerPID: ownerPID, selfPID: ProcessInfo.processInfo.processIdentifier) == .removed {
            drop(id)
            relayout()
        }
        Task { await poll() }
    }

    /// Unsharing takes effect at once: the stream stops and the tile leaves the canvas before any
    /// window-list fetch.
    func remove(_ id: CGWindowID) {
        set.remove(id)
        drop(id)
        relayout()
    }

    func move(from: Int, to: Int) {
        set.move(from: from, to: to)
        relayout()
    }

    private func drop(_ id: CGWindowID) {
        if let capture = captures.removeValue(forKey: id) { Task { await capture.stop() } }
        surfaces[id] = nil
        suspended.remove(id)
        frames[id] = nil
        info[id] = nil
        availability[id] = nil
    }

    private func poll() async {
        guard !polling else { return }
        polling = true
        defer { polling = false }
        let snapshot = set.generation
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
        wallpaper.update(source: settings.wallpaper, content: content)
        let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })

        set.prune(present: Set(byID.keys), snapshot: snapshot)
        for id in Array(captures.keys) where !set.ids.contains(id) { drop(id) }
        for id in set.ids {
            guard let window = byID[id] else { continue }
            info[id] = (window.title ?? "", window.owningApplication.flatMap { NSRunningApplication(processIdentifier: $0.processID) })
            if let old = frames[id], let capture = captures[id],
               old.size != window.frame.size || WindowCapture.backingScale(for: old) != WindowCapture.backingScale(for: window.frame) {
                Task { await capture.resize(to: window.frame) }
            }
            frames[id] = window.frame
            if captures[id] == nil {
                let capture = WindowCapture(window: window) { [weak self] event in self?.handle(event, for: id) }
                captures[id] = capture
                Task { await capture.start() }
            }
        }
        // A window with no frame yet is left out: it joins the canvas on its first frame.
        availability = Dictionary(uniqueKeysWithValues: set.ids.compactMap { id in
            suspended.contains(id) ? (id, .minimised) : surfaces[id] == nil ? nil : (id, .available)
        })
        onScreen = Self.onScreenWindows()
        relayout()
    }

    private func handle(_ event: WindowCapture.Event, for id: CGWindowID) {
        guard captures[id] != nil else { return }
        switch event {
        case .frame(let surface):
            let wasOff = surfaces[id] == nil || suspended.contains(id)
            surfaces[id] = surface
            suspended.remove(id)
            if wasOff {
                availability[id] = .available
                relayout()
            } else if let i = model.tiles.firstIndex(where: { $0.id == id }) {
                model.tiles[i].surface = surface
                model.changed()
            }
        case .suspended:
            suspended.insert(id)
            availability[id] = .minimised
            relayout()
        case .stopped:
            // Forget the dead stream; the next poll starts a fresh one if the window still exists.
            captures[id] = nil
            surfaces[id] = nil
            availability[id] = nil
            relayout()
        }
    }

    private func relayout() {
        let ids = set.laidOut(availability: availability).filter { frames[$0] != nil }
        let rects = Layout.frames(sources: ids.map { frames[$0]! }, mode: settings.layout, margin: settings.margin)
        model.tiles = zip(ids, rects).map { CanvasModel.Tile(id: $0, surface: surfaces[$0], canvasFrame: $1) }
        model.placed = zip(ids, rects).map { PlacedWindow(id: $0, screenFrame: frames[$0]!, canvasFrame: $1) }
        model.changed()
        onChange?()
    }

    /// Every visible on-screen window below the menu bar's level, with its CG global bounds, front
    /// to back. Invisible overlays and system chrome are left out so they can't hide the pointer.
    static func onScreenWindows() -> [OnScreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        return list.compactMap { w in
            guard (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  (w[kCGWindowLayer as String] as? Int ?? 0) < menuBarLevel,
                  let n = w[kCGWindowNumber as String] as? CGWindowID,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b) else { return nil }
            return OnScreenWindow(id: n, frame: rect)
        }
    }
}
