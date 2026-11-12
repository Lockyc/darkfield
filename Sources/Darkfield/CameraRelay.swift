import AppKit
import CoreMediaIO
import DarkfieldCore
import os
import SystemExtensions

/// darkfield's side of Darkfield Camera: activates the camera extension, writes processed frames
/// into its sink stream, and reports whether any app is streaming from it.
@MainActor
final class CameraRelay: NSObject, ObservableObject {
    enum State: Equatable {
        case notInThisBuild
        case activating
        case needsApproval
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .activating
    /// True while some app streams from Darkfield Camera.
    var onClientStreaming: ((Bool) -> Void)?

    static let extensionID = "com.lockyc.darkfield.camera"
    private let sink = Sink()
    private var device: CMIOObjectID?
    private var sourceStream: CMIOObjectID?

    func activate() {
        let embedded = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/SystemExtensions/\(Self.extensionID).systemextension")
        guard FileManager.default.fileExists(atPath: embedded.path) else {
            state = .notInThisBuild
            return
        }
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.extensionID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        watchDevices()
    }

    /// Called on the capture queue with each processed frame.
    nonisolated func send(_ frame: CMSampleBuffer) { sink.enqueue(frame) }

    func openApprovalSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
    }

    // MARK: CoreMediaIO

    /// The device list's listener reports the device going away, so the sink closes with it.
    private func watchDevices() {
        var address = Self.address(kCMIOHardwarePropertyDevices)
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.connect() }
        }
        connect()
    }

    /// A process that is already running never sees a camera that a newly installed or replaced
    /// extension publishes: not in CoreMediaIO's device list, its listener, or AVFoundation's
    /// notifications. Only a new process does. So once activation succeeds, darkfield relaunches
    /// if the device still isn't visible — at most once per extension version, so a device that
    /// never appears can't cause a relaunch loop.
    private func relaunchIfDeviceUnseen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.device == nil else { return }
                let version = Bundle(url: Bundle.main.bundleURL
                    .appendingPathComponent("Contents/Library/SystemExtensions/\(Self.extensionID).systemextension"))?
                    .infoDictionary?["CFBundleVersion"] as? String ?? "?"
                let key = "cameraRelaunchedForExtension"
                guard UserDefaults.standard.string(forKey: key) != version else {
                    CameraController.log.error("relay: device not visible after relaunching for \(version)")
                    return
                }
                UserDefaults.standard.set(version, forKey: key)
                CameraController.log.info("relay: relaunching to see extension \(version)")
                let reopen = Process()
                reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
                reopen.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
                try? reopen.run()
                NSApp.terminate(nil)
            }
        }
    }

    private func connect() {
        let found = Self.objects(CMIOObjectID(kCMIOObjectSystemObject), kCMIOHardwarePropertyDevices)
            .first { Self.string($0, kCMIODevicePropertyDeviceUID) == CameraIDs.device.uuidString }
        guard let found else {
            if device != nil { CameraController.log.info("relay: device gone") }
            device = nil
            sourceStream = nil
            sink.close()
            return
        }
        guard found != device else { return }
        device = found
        let streams = Self.objects(found, kCMIODevicePropertyStreams)
        let sinkName = "\(CameraIDs.deviceName) Input"
        guard let sinkStream = streams.first(where: { Self.string($0, kCMIOObjectPropertyName) == sinkName }),
              let source = streams.first(where: { $0 != sinkStream }) else {
            state = .failed("Darkfield Camera is missing a stream")
            return
        }
        sourceStream = source
        sink.open(device: found, stream: sinkStream)
        var address = CMIOObjectPropertyAddress(mSelector: CameraIDs.clientsSelector,
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        CMIOObjectAddPropertyListenerBlock(source, &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.readClients() }
        }
        readClients()
        CameraController.log.info("relay: connected")
    }

    private func readClients() {
        guard let sourceStream else { return }
        var address = CMIOObjectPropertyAddress(mSelector: CameraIDs.clientsSelector,
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &value) {
            CMIOObjectGetPropertyData(sourceStream, &address, 0, nil, UInt32(MemoryLayout<CFString?>.size), &used, $0)
        }
        let streaming = status == noErr && (value?.takeRetainedValue() as String?) == "1"
        CameraController.log.info("relay: clients streaming=\(streaming)")
        onClientStreaming?(streaming)
    }

    private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func objects(_ owner: CMIOObjectID, _ selector: Int) -> [CMIOObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(owner, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(owner, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }

    private static func string(_ object: CMIOObjectID, _ selector: Int) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &value) {
            CMIOObjectGetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<CFString?>.size), &used, $0)
        }
        guard status == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}

extension CameraRelay: OSSystemExtensionRequestDelegate {
    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        MainActor.assumeIsolated { state = .needsApproval }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        MainActor.assumeIsolated {
            state = .ready
            connect()
            relaunchIfDeviceUnseen()
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            CameraController.log.error("relay: activation failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }
}

/// The sink stream's buffer queue, filled from the capture queue.
private final class Sink: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: CMSimpleQueue?
    private var device: CMIOObjectID = 0
    private var stream: CMIOObjectID = 0

    func open(device: CMIOObjectID, stream: CMIOObjectID) {
        close()
        var q: Unmanaged<CMSimpleQueue>?
        let copied = CMIOStreamCopyBufferQueue(stream, { _, _, _ in }, nil, &q)
        guard copied == noErr, let q else {
            CameraController.log.error("relay: sink queue failed: \(copied)")
            return
        }
        lock.withLock {
            queue = q.takeRetainedValue()
            self.device = device
            self.stream = stream
        }
        let started = CMIODeviceStartStream(device, stream)
        CameraController.log.info("relay: sink started=\(started)")
    }

    private var sent = 0
    private var dropped = 0

    func close() {
        let (device, stream, open) = lock.withLock { () -> (CMIOObjectID, CMIOObjectID, Bool) in
            defer { queue = nil }
            return (self.device, self.stream, queue != nil)
        }
        if open { CMIODeviceStopStream(device, stream) }
    }

    func enqueue(_ frame: CMSampleBuffer) {
        lock.withLock {
            guard let queue else { return }
            if CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) {
                CMSimpleQueueEnqueue(queue, element: Unmanaged.passRetained(frame).toOpaque())
                sent += 1
            } else {
                dropped += 1
            }
            if (sent + dropped) % 90 == 0 {
                CameraController.log.info("relay: sink sent=\(self.sent) dropped=\(self.dropped) capacity=\(CMSimpleQueueGetCapacity(queue))")
            }
        }
    }
}
