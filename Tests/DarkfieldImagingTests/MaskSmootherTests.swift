import CoreImage
import CoreVideo
import DarkfieldImaging
import XCTest

final class MaskSmootherTests: XCTestCase {
    /// A one-channel 8×8 mask filled with `value`, as Vision's person segmentation returns.
    private func mask(_ value: UInt8) throws -> CVPixelBuffer {
        var b: CVPixelBuffer?
        CVPixelBufferCreate(nil, 8, 8, kCVPixelFormatType_OneComponent8,
                            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &b)
        let buffer = try XCTUnwrap(b)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        memset(base, Int32(value), CVPixelBufferGetBytesPerRow(buffer) * 8)
        return buffer
    }

    private let context = CIContext(options: [.cacheIntermediates: false])

    /// The centre value of a smoothed mask, read back without colour management.
    private func centre(_ image: CIImage) throws -> Int {
        let buffer = try mask(0)
        context.render(image, to: buffer, bounds: image.extent, colorSpace: nil)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        return Int(base[4 * CVPixelBufferGetBytesPerRow(buffer) + 4])
    }

    func testAPersonWhoLeavesFadesOutOfTheMask() throws {
        // 0188705: the mask latched at 255 once the person was gone; fixed, it decays by 70% a frame.
        let s = MaskSmoother()
        let values = try [255, 0, 0, 0].map { try centre(s.smooth(mask($0))) }
        for (got, want) in zip(values, [255, 77, 23, 7]) {
            XCTAssertEqual(Double(got), Double(want), accuracy: 2, "decay \(values)")
        }
    }

    func testASteadyMaskIsNotSkewedByAGammaRoundTrip() throws {
        let s = MaskSmoother()
        for _ in 0..<4 {
            XCTAssertEqual(Double(try centre(s.smooth(mask(128)))), 128, accuracy: 1)
        }
    }

    func testResetStartsFresh() throws {
        let s = MaskSmoother()
        _ = s.smooth(try mask(255))
        s.reset()
        XCTAssertEqual(try centre(s.smooth(mask(0))), 0)
    }
}
