import CoreImage
import CoreVideo

/// The person mask, 70/30 with the previous frame's, so its edge doesn't flicker.
///
/// Masks are read and written without colour management: they are coverage values, and a gamma
/// conversion on each save would skew the blend and make the mask lag behind you.
public final class MaskSmoother {
    private let context: CIContext
    private var previous: CIImage?
    private var pool: CVPixelBufferPool?
    private var size: CGSize = .zero

    public init(context: CIContext = CIContext(options: [.cacheIntermediates: false])) {
        self.context = context
    }

    /// Forgets the previous mask, so the next starts fresh.
    public func reset() { previous = nil }

    /// This frame's smoothed mask, at `raw`'s size, backed by a buffer of its own.
    public func smooth(_ raw: CVPixelBuffer) -> CIImage {
        var mask = CIImage(cvPixelBuffer: raw, options: [.colorSpace: NSNull()])
        let rawSize = mask.extent.size
        if let previous, rawSize == size {
            mask = previous.applyingFilter("CIDissolveTransition",
                                           parameters: [kCIInputTargetImageKey: mask, kCIInputTimeKey: 0.7])
        }
        // Vision reuses its result buffers, so the mask kept for the next frame is our own copy.
        if rawSize != size {
            size = rawSize
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_OneComponent8,
                kCVPixelBufferWidthKey as String: Int(rawSize.width),
                kCVPixelBufferHeightKey as String: Int(rawSize.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
            pool = nil
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        }
        var copy: CVPixelBuffer?
        if let pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &copy) }
        guard let copy else { return mask }
        context.render(mask, to: copy, bounds: mask.extent, colorSpace: nil)
        let kept = CIImage(cvPixelBuffer: copy, options: [.colorSpace: NSNull()])
        previous = kept
        return kept
    }
}
