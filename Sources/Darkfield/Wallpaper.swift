import AppKit
import DarkfieldCore
import ScreenCaptureKit

/// The canvas background. A display source streams that display's system wallpaper window — the
/// on-screen `Wallpaper` window owned by `com.apple.WindowManager` — so rotating and dynamic
/// wallpapers show live; an image source is a fixed picture.
@MainActor
final class Wallpaper {
    private(set) var image: CGImage?
    private(set) var surface: IOSurface?
    var onChange: (() -> Void)?

    private var source: WallpaperSource?
    private var capture: WindowCapture?

    /// Called with each fresh shareable-content snapshot; (re)targets the wallpaper window when the
    /// source or the system's wallpaper window changes.
    func update(source: WallpaperSource, content: SCShareableContent) {
        if case .image(let url) = source {
            if self.source != source {
                self.source = source
                stopCapture()
                image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                surface = nil
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
        if self.source == source, capture?.windowID == window.windowID { return }
        self.source = source
        image = nil
        stopCapture()
        let capture = WindowCapture(window: window) { [weak self] event in
            guard let self, case .frame(let s) = event else { return }
            self.surface = s
            self.onChange?()
        }
        self.capture = capture
        Task { try? await capture.start() }
    }

    private func stopCapture() {
        if let capture { Task { await capture.stop() } }
        capture = nil
    }
}
