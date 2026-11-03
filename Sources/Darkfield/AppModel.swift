import AppKit
import Combine
import DarkfieldCore

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
    /// Set while a hotkey recorder is listening, so the live hotkeys don't swallow the keystroke.
    @Published var recordingHotKey = false { didSet { onRecording?(recordingHotKey) } }

    var onSettings: ((Settings) -> Void)?
    var onRecording: ((Bool) -> Void)?
    let captures: CaptureManager
    let canvas: CanvasModel

    init(settings: Settings, captures: CaptureManager, canvas: CanvasModel) {
        self.settings = settings
        self.captures = captures
        self.canvas = canvas
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

    func openScreenRecordingSettings() {
        CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
