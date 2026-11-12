import CoreMediaIO
import DarkfieldCore
import Foundation
import IOKit.audio
import os

private let log = Logger(subsystem: "com.lockyc.darkfield.camera", category: "extension")

/// The camera extension. It never opens a camera: darkfield writes processed frames into the
/// sink stream, and the source stream relays the latest one to video apps at 30 fps — or a plain
/// dark frame when darkfield has sent nothing recent.
final class Provider: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var device: Device!

    override init() {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: nil)
        device = Device()
        do { try provider.addDevice(device.device) } catch { log.fault("addDevice failed: \(error)") }
    }

    func connect(to client: CMIOExtensionClient) throws {}
    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let p = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) { p.manufacturer = "darkfield" }
        return p
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}

final class Device: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var source: SourceStream!
    private var sink: SinkStream!
    /// Guards everything below, and runs the frame timer.
    private let queue = DispatchQueue(label: "com.lockyc.darkfield.camera.relay")
    private var latest: CVPixelBuffer?
    private var latestAt: Date?
    private var timer: DispatchSourceTimer?
    private var clientCount = 0
    private let dark: CVPixelBuffer
    private let format: CMVideoFormatDescription

    override init() {
        dark = Self.darkFrame()
        var f: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: dark, formatDescriptionOut: &f)
        format = f!
        super.init()
        device = CMIOExtensionDevice(localizedName: CameraIDs.deviceName, deviceID: CameraIDs.device, legacyDeviceID: nil, source: self)
        let duration = CMTime(value: 1, timescale: CMTimeScale(CameraIDs.frameRate))
        let streamFormat = CMIOExtensionStreamFormat(formatDescription: format, maxFrameDuration: duration, minFrameDuration: duration, validFrameDurations: nil)
        source = SourceStream(format: streamFormat, device: self)
        sink = SinkStream(format: streamFormat, device: self)
        do {
            try device.addStream(source.stream)
            try device.addStream(sink.stream)
        } catch {
            log.fault("addStream failed: \(error)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> { [.deviceTransportType, .deviceModel] }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let p = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) { p.transportType = kIOAudioDeviceTransportTypeVirtual }
        if properties.contains(.deviceModel) { p.model = CameraIDs.deviceName }
        return p
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    /// A frame from darkfield.
    func received(_ pixels: CVPixelBuffer) {
        queue.async {
            self.latest = pixels
            self.latestAt = Date()
        }
    }

    /// Called once per app that starts streaming; the relay runs while any app is.
    func sourceStarted() {
        queue.async { [weak self] in
            guard let self else { return }
            clientCount += 1
            log.info("source: start, clients=\(self.clientCount), last frame \(self.latestAt.map { -$0.timeIntervalSinceNow } ?? -1)s ago")
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: 1.0 / Double(CameraIDs.frameRate), leeway: .milliseconds(2))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
            source.clientsChanged(streaming: true)
        }
    }

    func sourceStopped() {
        queue.async {
            self.clientCount = max(self.clientCount - 1, 0)
            guard self.clientCount == 0 else { return }
            self.timer?.cancel()
            self.timer = nil
            self.source.clientsChanged(streaming: false)
        }
    }

    private func tick() {
        let fresh = !IdleFrame.isStale(lastSinkFrame: latestAt, now: Date())
        let pixels = fresh ? latest ?? dark : dark
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(CameraIDs.frameRate)),
                                        presentationTimeStamp: now, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        var f: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels, formatDescriptionOut: &f)
        guard let f else { return }
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixels, formatDescription: f,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return }
        source.stream.send(sample, discontinuity: [], hostTimeInNanoseconds: UInt64(now.seconds * Double(NSEC_PER_SEC)))
    }

    /// Plain black, opaque, at the output size — no text or mark of any kind.
    private static func darkFrame() -> CVPixelBuffer {
        var b: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        CVPixelBufferCreate(nil, CameraIDs.width, CameraIDs.height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &b)
        let buffer = b!
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<CameraIDs.height {
            let row = base + y * rowBytes
            for x in 0..<CameraIDs.width {
                row[x * 4] = 0; row[x * 4 + 1] = 0; row[x * 4 + 2] = 0; row[x * 4 + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}

/// What video apps read. Publishes whether any app is streaming as the custom property
/// `CameraIDs.clientsProperty`, which darkfield watches to run the physical camera on demand.
final class SourceStream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let format: CMIOExtensionStreamFormat
    private unowned let device: Device
    private let clients = CMIOExtensionProperty(rawValue: CameraIDs.clientsProperty)
    private var streaming = false

    init(format: CMIOExtensionStreamFormat, device: Device) {
        self.format = format
        self.device = device
        super.init()
        stream = CMIOExtensionStream(localizedName: CameraIDs.deviceName, streamID: CameraIDs.sourceStream,
                                     direction: .source, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }
    var availableProperties: Set<CMIOExtensionProperty> { [.streamActiveFormatIndex, .streamFrameDuration, clients] }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let p = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { p.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) { p.frameDuration = CMTime(value: 1, timescale: CMTimeScale(CameraIDs.frameRate)) }
        if properties.contains(clients) {
            p.setPropertyState(clientsState, forProperty: clients)
        }
        return p
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }
    func startStream() throws { device.sourceStarted() }
    func stopStream() throws { device.sourceStopped() }

    func clientsChanged(streaming: Bool) {
        self.streaming = streaming
        stream.notifyPropertiesChanged([clients: clientsState])
    }

    private var clientsState: CMIOExtensionPropertyState<AnyObject> {
        CMIOExtensionPropertyState(value: (streaming ? "1" : "0") as NSString as AnyObject)
    }
}

/// What darkfield writes into.
final class SinkStream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let format: CMIOExtensionStreamFormat
    private unowned let device: Device
    private var client: CMIOExtensionClient?

    init(format: CMIOExtensionStreamFormat, device: Device) {
        self.format = format
        self.device = device
        super.init()
        stream = CMIOExtensionStream(localizedName: "\(CameraIDs.deviceName) Input", streamID: CameraIDs.sinkStream,
                                     direction: .sink, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }
    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration, .streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let p = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { p.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) { p.frameDuration = CMTime(value: 1, timescale: CMTimeScale(CameraIDs.frameRate)) }
        if properties.contains(.streamSinkBufferQueueSize) { p.sinkBufferQueueSize = 1 }
        if properties.contains(.streamSinkBuffersRequiredForStartup) { p.sinkBuffersRequiredForStartup = 1 }
        return p
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        self.client = client
        return true
    }

    func startStream() throws {
        log.info("sink: start, client=\(self.client != nil)")
        consume()
    }

    func stopStream() throws {
        log.info("sink: stop after \(self.consumed) frames")
        client = nil
    }

    private var consumed = 0
    private var errors = 0

    private func consume() {
        guard let client else { return }
        stream.consumeSampleBuffer(from: client) { [weak self] sample, sequence, _, _, error in
            guard let self else { return }
            if let error {
                errors += 1
                if errors % 30 == 1 {
                    let e = error as NSError
                    log.error("sink: consume error #\(self.errors, privacy: .public) \(e.domain, privacy: .public) \(e.code, privacy: .public) \(e.localizedDescription, privacy: .public)")
                }
            }
            if let sample, let pixels = CMSampleBufferGetImageBuffer(sample) {
                consumed += 1
                if consumed % 90 == 1 { log.info("sink: \(self.consumed) frames") }
                device.received(pixels)
                let now = CMClockGetTime(CMClockGetHostTimeClock())
                stream.notifyScheduledOutputChanged(CMIOExtensionScheduledOutput(
                    sequenceNumber: sequence, hostTimeInNanoseconds: UInt64(now.seconds * Double(NSEC_PER_SEC))))
            }
            // Keep consuming while darkfield is connected; a nil sample just means none was ready.
            if self.client != nil {
                DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + (sample == nil ? 0.005 : 0)) { self.consume() }
            }
        }
    }
}
