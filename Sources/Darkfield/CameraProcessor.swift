import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import DarkfieldCore
import Vision

/// Turns a raw camera frame into Darkfield Camera's frame: the background blurred behind the
/// presenter, cropped by `Framing`, scaled to 1920×1080 BGRA. Used from the capture queue only.
final class CameraProcessor {
    static let width = 1920
    static let height = 1080

    private let context = CIContext(options: [.cacheIntermediates: false])
    private var pool: CVPixelBufferPool?
    private var framing = Framing()
    private var lastTime: CMTime?
    /// The previous frame's mask, blended into the next so its edge doesn't flicker.
    private var previousMask: CIImage?
    private var maskPool: CVPixelBufferPool?
    private var maskSize: CGSize = .zero
    private let segmentation: VNGeneratePersonSegmentationRequest = {
        let r = VNGeneratePersonSegmentationRequest()
        r.qualityLevel = .balanced
        r.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return r
    }()
    private let faces = VNDetectFaceRectanglesRequest()

    init() {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.width,
            kCVPixelBufferHeightKey as String: Self.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
    }

    func process(_ pixels: CVPixelBuffer, time: CMTime, settings: CameraSettings) -> CMSampleBuffer? {
        let source = CIImage(cvPixelBuffer: pixels)
        let extent = source.extent
        let dt = lastTime.map { min(max((time - $0).seconds, 0), 0.1) } ?? 1.0 / 30
        lastTime = time

        var requests: [VNRequest] = []
        if settings.blur { requests.append(segmentation) }
        if settings.framing { requests.append(faces) }
        if !requests.isEmpty { try? VNImageRequestHandler(cvPixelBuffer: pixels).perform(requests) }

        let face = settings.framing ? Self.largestFace(faces.results) : nil
        let crop = framing.step(subject: face, tightness: settings.framingTightness,
                                sourceAspect: extent.width / extent.height, dt: dt)
        // The crop in Core Image's bottom-left pixel space.
        let r = CGRect(x: crop.minX * extent.width, y: (1 - crop.maxY) * extent.height,
                       width: crop.width * extent.width, height: crop.height * extent.height)

        var image = source
        if settings.blur, let mask = smoothedMask(extent: extent) {
            // The radius is set in output pixels; the crop is scaled up to the output, so blur the
            // source by the radius shrunk by that scale.
            let radius = BlurScale.radius(strength: settings.blurStrength, height: Double(Self.height)) * Double(r.height) / Double(Self.height)
            let blurred = source.clampedToExtent().applyingGaussianBlur(sigma: radius / 2).cropped(to: extent)
            let blend = CIFilter.blendWithMask()
            blend.inputImage = source
            blend.backgroundImage = blurred
            blend.maskImage = mask
            image = blend.outputImage ?? source
        } else {
            previousMask = nil
        }

        let scaled = image.cropped(to: r)
            .transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY)
                .concatenating(CGAffineTransform(scaleX: CGFloat(Self.width) / r.width, y: CGFloat(Self.height) / r.height)))
        guard let pool, let out = Self.buffer(from: pool) else { return nil }
        context.render(scaled, to: out, bounds: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return Self.sampleBuffer(out, time: time)
    }

    /// Largest face, flipped from Vision's bottom-left origin to `Framing`'s top-left.
    private static func largestFace(_ results: [VNFaceObservation]?) -> CGRect? {
        guard let b = results?.max(by: { $0.boundingBox.width < $1.boundingBox.width })?.boundingBox else { return nil }
        return CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
    }

    /// This frame's person mask, 70/30 with the previous one, scaled to the source.
    private func smoothedMask(extent: CGRect) -> CIImage? {
        guard let raw = segmentation.results?.first?.pixelBuffer else { return nil }
        var mask = CIImage(cvPixelBuffer: raw)
        let size = mask.extent.size
        if let previous = previousMask, size == maskSize {
            let now = mask.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0.7, y: 0, z: 0, w: 0)])
            let then = previous.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0.3, y: 0, z: 0, w: 0)])
            mask = now.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: then])
        }
        // Vision reuses its result buffers, so the mask kept for the next frame is our own copy.
        if size != maskSize {
            maskSize = size
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_OneComponent8,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
            maskPool = nil
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &maskPool)
        }
        if let maskPool, let copy = Self.buffer(from: maskPool) {
            context.render(mask, to: copy)
            previousMask = CIImage(cvPixelBuffer: copy)
            mask = previousMask!
        }
        return mask.transformed(by: CGAffineTransform(scaleX: extent.width / size.width, y: extent.height / size.height))
    }

    private static func buffer(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var b: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &b)
        return b
    }

    static func sampleBuffer(_ pixels: CVPixelBuffer, time: CMTime) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels, formatDescriptionOut: &format)
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixels, formatDescription: format,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        return sample
    }
}
