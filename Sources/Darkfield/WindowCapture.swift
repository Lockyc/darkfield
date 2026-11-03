import AppKit
import CoreMedia
import IOSurface
import ScreenCaptureKit

/// One window streamed through ScreenCaptureKit: desktop-independent (nothing overlapping it is
/// captured), no cursor, at most 30 fps, at the pixel scale of the display the window is on.
/// Control (`start`, `stop`, `resize`) runs on the main actor so it is serialised; frames arrive on
/// a private queue.
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    enum Event {
        case frame(IOSurface)
        /// The window can't be captured where it is (minimised).
        case suspended
        /// The stream ended or never started; the capture must be recreated.
        case stopped
    }

    let windowID: CGWindowID
    private let onEvent: @MainActor (Event) -> Void
    @MainActor private var stream: SCStream?
    private let queue = DispatchQueue(label: "darkfield.capture")

    @MainActor
    init(window: SCWindow, onEvent: @escaping @MainActor (Event) -> Void) {
        windowID = window.windowID
        self.onEvent = onEvent
        super.init()
        stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window),
                          configuration: Self.configuration(for: window.frame), delegate: self)
    }

    /// Pixel size = the window's points × the backing scale of the display holding most of it.
    @MainActor
    static func configuration(for frame: CGRect) -> SCStreamConfiguration {
        let cfg = SCStreamConfiguration()
        let scale = backingScale(for: frame)
        cfg.width = max(2, Int(frame.width * scale))
        cfg.height = max(2, Int(frame.height * scale))
        cfg.showsCursor = false
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.queueDepth = 4
        return cfg
    }

    /// The backing scale of the screen a CG-global `frame` mostly overlaps.
    @MainActor
    static func backingScale(for frame: CGRect) -> CGFloat {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let best = NSScreen.screens.max { a, b in
            overlap(a, frame, primaryHeight) < overlap(b, frame, primaryHeight)
        }
        return best?.backingScaleFactor ?? 2
    }

    private static func overlap(_ screen: NSScreen, _ cg: CGRect, _ primaryHeight: CGFloat) -> CGFloat {
        let f = screen.frame
        let screenCG = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
        let i = screenCG.intersection(cg)
        return i.isNull ? 0 : i.width * i.height
    }

    @MainActor
    func start() async {
        guard let stream else { return }
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            onEvent(.stopped)
        }
    }

    @MainActor
    func stop() async {
        let s = stream
        stream = nil
        try? await s?.stopCapture()
    }

    /// Re-targets the pixel size after the window is resized or changes display, so content is
    /// never stretched or soft.
    @MainActor
    func resize(to frame: CGRect) async {
        try? await stream?.updateConfiguration(Self.configuration(for: frame))
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return }
        let event: Event
        switch status {
        case .complete:
            guard let pixels = CMSampleBufferGetImageBuffer(buffer),
                  let surface = CVPixelBufferGetIOSurface(pixels)?.takeUnretainedValue() else { return }
            event = .frame(surface)
        case .suspended, .blank:
            event = .suspended
        default:
            return
        }
        let onEvent = onEvent
        Task { @MainActor in onEvent(event) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let onEvent = onEvent
        Task { @MainActor in onEvent(.stopped) }
    }
}
