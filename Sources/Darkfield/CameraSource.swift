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
    /// Frames arrive here.
    private let queue = DispatchQueue(label: "com.lockyc.darkfield.camera.frames")
    /// Starting, stopping and configuring the session happen here, never on the frame queue:
    /// `startRunning` waits on the frame queue, so running it there stalls it for seconds.
    private let sessionQueue = DispatchQueue(label: "com.lockyc.darkfield.camera.session")
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

    nonisolated private static func devices() -> [AVCaptureDevice] {
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

    /// Every touch of the session runs on the session queue, in call order: a stop followed by a
    /// start can't interleave their input changes. A camera that fails to open leaves nothing
    /// running, so the next start for it tries again.
    func start(id: String) {
        guard runningID != id else { return }
        stop()
        runningID = id
        let session = session
        sessionQueue.async { [weak self] in
            guard let device = Self.devices().first(where: { $0.uniqueID == id }),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                CameraController.log.error("capture: can't open camera")
                Task { @MainActor in
                    if self?.runningID == id { self?.runningID = nil }
                }
                return
            }
            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            Self.preferOutputFormat(device)
            session.startRunning()
            CameraController.log.info("capture: started, running=\(session.isRunning) inputs=\(session.inputs.count)")
        }
    }

    func stop() {
        guard runningID != nil else { return }
        runningID = nil
        let session = session
        sessionQueue.async {
            session.stopRunning()
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            session.commitConfiguration()
            CameraController.log.info("capture: stopped, running=\(session.isRunning) inputs=\(session.inputs.count)")
        }
    }

    /// Darkfield Camera's own size and rate (`CameraIDs`) when the camera has it, else its largest
    /// format at that rate up to that height.
    nonisolated private static func preferOutputFormat(_ device: AVCaptureDevice) {
        let rate = Double(CameraIDs.frameRate)
        func supportsRate(_ f: AVCaptureDevice.Format) -> Bool {
            f.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= rate && $0.maxFrameRate >= rate }
        }
        let formats = device.formats.filter(supportsRate)
        let dims = { (f: AVCaptureDevice.Format) in CMVideoFormatDescriptionGetDimensions(f.formatDescription) }
        let best = formats.first { dims($0).width == CameraIDs.width && dims($0).height == CameraIDs.height }
            ?? formats.filter { dims($0).height <= CameraIDs.height }.max { dims($0).width < dims($1).width }
        guard let best, (try? device.lockForConfiguration()) != nil else { return }
        device.activeFormat = best
        let duration = CMTime(value: 1, timescale: CMTimeScale(CameraIDs.frameRate))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.unlockForConfiguration()
    }
}

private final class FrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    private var count = 0

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        count += 1
        if count % 60 == 0 { CameraController.log.info("capture: \(self.count) frames") }
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixels, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}
