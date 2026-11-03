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
    var settings = Settings() { didSet { relayout() } }
    var onChange: (() -> Void)?

    private let model: CanvasModel
    private let wallpaper = Wallpaper()
    private var captures: [CGWindowID: WindowCapture] = [:]
    private var surfaces: [CGWindowID: IOSurface] = [:]
    private var suspended: Set<CGWindowID> = []
    private var frames: [CGWindowID: CGRect] = [:]
    private(set) var zOrder: [CGWindowID] = []
    private var content: SCShareableContent?
    private var timer: Timer?

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
        let order = Self.onScreenOrder()
        let candidates = content.windows.filter { $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 }
        guard let window = candidates.min(by: { (order[$0.windowID] ?? .max) < (order[$1.windowID] ?? .max) }) else { return }
        toggle(window.windowID, ownerPID: app.processIdentifier)
    }

    func toggle(_ id: CGWindowID, ownerPID: pid_t) {
        set.toggle(id, ownerPID: ownerPID, selfPID: ProcessInfo.processInfo.processIdentifier)
        Task { await poll() }
    }

    func remove(_ id: CGWindowID) {
        set.remove(id)
        Task { await poll() }
    }

    func move(from: Int, to: Int) {
        set.move(from: from, to: to)
        relayout()
    }

    private func poll() async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
        self.content = content
        wallpaper.update(source: settings.wallpaper, content: content)
        let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })

        for id in set.ids where byID[id] == nil { set.remove(id) }
        for (id, capture) in captures where !set.ids.contains(id) {
            Task { await capture.stop() }
            captures[id] = nil
            surfaces[id] = nil
            suspended.remove(id)
        }
        for id in set.ids {
            guard let window = byID[id] else { continue }
            info[id] = (window.title ?? "", window.owningApplication.flatMap { NSRunningApplication(processIdentifier: $0.processID) })
            if let old = frames[id], old.size != window.frame.size, let capture = captures[id] {
                Task { try? await capture.resize(to: window.frame.size) }
            }
            frames[id] = window.frame
            if captures[id] == nil {
                let capture = WindowCapture(window: window) { [weak self] event in self?.handle(event, for: id) }
                captures[id] = capture
                Task { try? await capture.start() }
            }
        }
        info = info.filter { set.ids.contains($0.key) }
        frames = frames.filter { set.ids.contains($0.key) }
        // A window with no frame yet is left out: it joins the canvas on its first frame.
        availability = Dictionary(uniqueKeysWithValues: set.ids.compactMap { id in
            suspended.contains(id) ? (id, .minimised) : surfaces[id] == nil ? nil : (id, .available)
        })
        zOrder = Self.onScreenOrder().sorted { $0.value < $1.value }.map(\.key)
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

    /// Window id → front-to-back position among on-screen windows.
    static func onScreenOrder() -> [CGWindowID: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var order: [CGWindowID: Int] = [:]
        for (i, w) in list.enumerated() {
            if let n = w[kCGWindowNumber as String] as? CGWindowID { order[n] = i }
        }
        return order
    }
}
