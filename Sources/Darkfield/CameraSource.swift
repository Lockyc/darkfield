// AVCaptureSession isn't marked Sendable, but Apple documents starting and stopping it off the
// main thread — which is what the capture queue does with it.
@preconcurrency import AVFoundation
import DarkfieldCore

/// The physical cameras, and capture from the one Darkfield Camera shows. Frames arrive on a
/// private serial queue, never the main thread.
@MainActor
final class CameraSource {
    private(set) var cameras: [CameraInfo] = []
    var onCamerasChanged: (() -> Void)?
    /// Called on the capture queue.
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)? {
        didSet { sink.onFrame = onFrame }
    }

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.lockyc.darkfield.camera.capture")
    private let sink = FrameSink()
    private var runningID: String?

    init() {
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(sink, queue: queue)
        session.beginConfiguration()
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    private static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    private func refresh() {
        let all = Self.devices().map { CameraInfo(id: $0.uniqueID, name: $0.localizedName) }
        cameras = CameraChoice.selectable(all)
        // A running camera that went away leaves the session with a dead input; drop it so the
        // same camera starts cleanly when it comes back.
        if let id = runningID, !cameras.contains(where: { $0.id == id }) { stop() }
        onCamerasChanged?()
    }

    func start(id: String) {
        guard runningID != id else { return }
        stop()
        guard let device = Self.devices().first(where: { $0.uniqueID == id }),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        Self.prefer1080p30(device)
        runningID = id
        let session = session
        queue.async { session.startRunning() }
    }

    func stop() {
        guard runningID != nil else { return }
        runningID = nil
        let session = session
        queue.async {
            session.stopRunning()
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            session.commitConfiguration()
        }
    }

    /// 1920×1080 at 30 fps when the camera has it, else its largest format up to 1080 lines.
    private static func prefer1080p30(_ device: AVCaptureDevice) {
        func supports30(_ f: AVCaptureDevice.Format) -> Bool {
            f.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }
        }
        let formats = device.formats.filter(supports30)
        let dims = { (f: AVCaptureDevice.Format) in CMVideoFormatDescriptionGetDimensions(f.formatDescription) }
        let best = formats.first { dims($0).width == 1920 && dims($0).height == 1080 }
            ?? formats.filter { dims($0).height <= 1080 }.max { dims($0).width < dims($1).width }
        guard let best, (try? device.lockForConfiguration()) != nil else { return }
        device.activeFormat = best
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        device.unlockForConfiguration()
    }
}

private final class FrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixels, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}
