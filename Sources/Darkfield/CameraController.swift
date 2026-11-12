import AppKit
@preconcurrency import AVFoundation
import DarkfieldCore

/// Runs the physical camera when `CameraDemand` says so, processes each frame once, and hands
/// the result to the panel's preview and to `onProcessedFrame` (the camera extension).
@MainActor
final class CameraController: ObservableObject {
    @Published private(set) var cameras: [CameraInfo] = []
    @Published private(set) var status: CameraStatus = .off
    @Published private(set) var permission = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var demand = CameraDemand() { didSet { if demand != oldValue { reconcile() } } }
    var settings = CameraSettings() {
        didSet {
            pipeline.settings = settings
            if settings.deviceID != oldValue.deviceID { reconcile() }
        }
    }
    /// Called on the capture queue with every processed frame.
    var onProcessedFrame: ((CMSampleBuffer) -> Void)? { didSet { pipeline.onFrame = onProcessedFrame } }
    let previewLayer = AVSampleBufferDisplayLayer()

    private let source = CameraSource()
    private let pipeline: Pipeline

    init() {
        pipeline = Pipeline(preview: previewLayer)
        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = NSColor.black.cgColor
        source.onFrame = { [pipeline] pixels, time in pipeline.handle(pixels, time: time) }
        source.onCamerasChanged = { [weak self] in
            guard let self else { return }
            cameras = source.cameras
            reconcile()
        }
        cameras = source.cameras
    }

    func reconcile() {
        permission = AVCaptureDevice.authorizationStatus(for: .video)
        status = demand.status(chosenID: settings.deviceID, chosenName: settings.deviceName, connected: cameras)
        let run = demand.shouldRun(chosen: settings.deviceID, connected: cameras)
        if run, permission == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                Task { @MainActor [weak self] in self?.reconcile() }
            }
            return
        }
        if run, permission == .authorized, let id = settings.deviceID {
            source.start(id: id)
        } else {
            source.stop()
            previewLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        }
    }

    func openCameraSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }
}

/// The capture-queue half: the processor, a lock-guarded copy of the settings, and the outputs.
private final class Pipeline: @unchecked Sendable {
    private let lock = NSLock()
    private var _settings = CameraSettings()
    private var _onFrame: ((CMSampleBuffer) -> Void)?
    private let processor = CameraProcessor()
    private let preview: AVSampleBufferDisplayLayer

    init(preview: AVSampleBufferDisplayLayer) { self.preview = preview }

    var settings: CameraSettings {
        get { lock.withLock { _settings } }
        set { lock.withLock { _settings = newValue } }
    }
    var onFrame: ((CMSampleBuffer) -> Void)? {
        get { lock.withLock { _onFrame } }
        set { lock.withLock { _onFrame = newValue } }
    }

    func handle(_ pixels: CVPixelBuffer, time: CMTime) {
        guard let frame = processor.process(pixels, time: time, settings: settings) else { return }
        onFrame?(frame)
        // Display immediately: the preview shows what the call gets, not a re-timed copy.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(frame, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        let preview = preview
        DispatchQueue.main.async { preview.sampleBufferRenderer.enqueue(frame) }
    }
}
