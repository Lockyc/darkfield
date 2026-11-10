import AppKit
import DarkfieldCore
import ScreenCaptureKit

/// The canvas background. A display source captures that display's system wallpaper window — the
/// on-screen `Wallpaper` window owned by `com.apple.WindowManager` — so rotating and dynamic
/// wallpapers show; an image source is a fixed picture.
///
/// The wallpaper streams only while a window is shared (`live`). Otherwise darkfield takes one frame
/// and stops: any running capture makes macOS treat the Mac as screen sharing, which shows the
/// recording indicator and holds back notifications.
@MainActor
final class Wallpaper {
    private(set) var image: CGImage?
    private(set) var surface: IOSurface?
    var onChange: (() -> Void)?

    private var source: WallpaperSource?
    private var capture: WindowCapture?
    /// The wallpaper window `surface` came from.
    private var surfaceWindow: CGWindowID?
    private var live = false

    /// Called with each fresh shareable-content snapshot; (re)targets the wallpaper window when the
    /// source or the system's wallpaper window changes, and streams it only while `live`.
    func update(source: WallpaperSource, content: SCShareableContent, live: Bool) {
        self.live = live
        if case .image(let url) = source {
            if self.source != source {
                self.source = source
                stopCapture()
                image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                surface = nil
                surfaceWindow = nil
                onChange?()
            }
            return
        }
        let display: CGDirectDisplayID = if case .display(let id) = source { id } else { CGMainDisplayID() }
        let bounds = CGDisplayBounds(display)
        guard let window = content.windows.first(where: {
            $0.owningApplication?.bundleIdentifier == "com.apple.WindowManager" && $0.title == "Wallpaper"
                && $0.isOnScreen && $0.frame == bounds
        }) else { return }
        let streaming = self.source == source && capture?.windowID == window.windowID
        let haveFrame = self.source == source && surfaceWindow == window.windowID && surface != nil
        if !live, haveFrame {
            stopCapture()
            return
        }
        if streaming { return }
        self.source = source
        image = nil
        stopCapture()
        let capture = WindowCapture(window: window) { [weak self] event in
            guard let self else { return }
            switch event {
            case .frame(let s):
                self.surface = s
                self.surfaceWindow = window.windowID
                self.onChange?()
                if !self.live { self.stopCapture() }
            case .stopped:
                // Recreated on the next update; the last frame stays up meanwhile.
                if self.capture?.windowID == window.windowID { self.capture = nil }
            case .suspended:
                break
            }
        }
        self.capture = capture
        Task { await capture.start() }
    }

    private func stopCapture() {
        if let capture { Task { await capture.stop() } }
        capture = nil
    }
}
