import CoreMedia
import IOSurface
import ScreenCaptureKit

/// One window streamed through ScreenCaptureKit: desktop-independent (nothing overlapping it is
/// captured), no cursor, at most 30 fps, at the window's backing pixel size.
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    enum Event {
        case frame(IOSurface)
        /// The window is on screen nowhere it can be captured from (minimised).
        case suspended
    }

    let windowID: CGWindowID
    private let onEvent: @MainActor (Event) -> Void
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "darkfield.capture")

    init(window: SCWindow, onEvent: @escaping @MainActor (Event) -> Void) {
        windowID = window.windowID
        self.onEvent = onEvent
        super.init()
        stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window),
                          configuration: Self.configuration(for: window.frame.size), delegate: self)
    }

    static func configuration(for size: CGSize) -> SCStreamConfiguration {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let cfg = SCStreamConfiguration()
        cfg.width = max(2, Int(size.width * scale))
        cfg.height = max(2, Int(size.height * scale))
        cfg.showsCursor = false
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.queueDepth = 4
        return cfg
    }

    func start() async throws {
        guard let stream else { return }
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    /// Re-targets the pixel size after the window is resized, so content is never stretched.
    func resize(to size: CGSize) async throws {
        try await stream?.updateConfiguration(Self.configuration(for: size))
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
        Task { @MainActor in onEvent(.suspended) }
    }
}
