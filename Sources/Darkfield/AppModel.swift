import AppKit
import Combine
import DarkfieldCore
import Sparkle

/// What the panel and settings window show and change. Settings changes persist and apply at once.
@MainActor
final class AppModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let id: CGWindowID
        let title: String
        let appName: String
        let icon: NSImage?
        let availability: Availability?
    }

    struct Display: Identifiable, Hashable {
        let id: CGDirectDisplayID
        let name: String
    }

    @Published var settings: Settings { didSet { if settings != oldValue { onSettings?(oldValue) } } }
    @Published private(set) var rows: [Row] = []
    @Published private(set) var displays: [Display] = []
    @Published private(set) var canCapture = CGPreflightScreenCaptureAccess()
    @Published var notice: String?
    /// Whether the floating preview window is on screen.
    @Published var previewShown = false
    var showPreview: (() -> Void)?
    /// How many hotkey recorders are listening. While any is, the live hotkeys are released so they
    /// don't swallow the keystroke.
    @Published var listeningRecorders = 0 {
        didSet { if (oldValue == 0) != (listeningRecorders == 0) { onRecording?(listeningRecorders > 0) } }
    }
    var recordingHotKey: Bool { listeningRecorders > 0 }
    @Published var windowHotKeyRefused = false
    @Published var pointerHotKeyRefused = false
    @Published var fitHotKeyRefused = false

    /// nil outside a bundle that names a feed (`swift run`); the panel's update button is then disabled.
    var updater: SPUStandardUpdaterController?
    var onSettings: ((Settings) -> Void)?
    var onRecording: ((Bool) -> Void)?
    let captures: CaptureManager
    let canvas: CanvasModel
    let camera = CameraController()
    let relay = CameraRelay()

    init(settings: Settings, captures: CaptureManager, canvas: CanvasModel) {
        self.settings = settings
        self.captures = captures
        self.canvas = canvas
        camera.settings = settings.camera
        refreshDisplays()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDisplays() }
        }
    }

    /// External displays a projector output can target: every screen but the one with the menu bar.
    var projectorDisplays: [Display] { displays.filter { $0.id != CGMainDisplayID() } }

    func refreshRows() {
        canCapture = CGPreflightScreenCaptureAccess()
        rows = captures.set.ids.map { id in
            let info = captures.info[id]
            return Row(id: id, title: info?.title ?? "", appName: info?.app?.localizedName ?? "",
                       icon: info?.app?.icon, availability: captures.availability[id])
        }
    }

    func refreshDisplays() {
        displays = NSScreen.screens.compactMap { s in
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return Display(id: n, name: s.localizedName)
        }
    }

    /// A menu of windows that can be shared, built fresh; choosing one shares it.
    func addWindowMenu() async -> NSMenu {
        let menu = NSMenu()
        let windows = await captures.shareableWindows()
        if windows.isEmpty {
            let item = NSMenuItem(title: "No other windows on screen", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        for w in windows {
            let app = w.owningApplication.flatMap { NSRunningApplication(processIdentifier: $0.processID) }
            let title = (w.title?.isEmpty == false ? w.title! : app?.localizedName) ?? "Window"
            let item = NSMenuItem(title: "\(app?.localizedName ?? "") — \(title)", action: #selector(MenuTarget.pick(_:)), keyEquivalent: "")
            item.target = MenuTarget.shared
            item.representedObject = { [weak self] in self?.captures.toggle(w.windowID, ownerPID: w.owningApplication?.processID ?? -1) } as () -> Void
            item.image = app?.icon.map { icon in
                let i = icon.copy() as! NSImage
                i.size = NSSize(width: 16, height: 16)
                return i
            }
            menu.addItem(item)
        }
        return menu
    }

    func openScreenRecordingSettings() {
        CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}

/// Runs the closure an NSMenuItem carries as its `representedObject`.
@MainActor
final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    @objc func pick(_ item: NSMenuItem) { (item.representedObject as? () -> Void)?() }
}
