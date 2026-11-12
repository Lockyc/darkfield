import Foundation

/// Darkfield Camera's source and effects.
public struct CameraSettings: Codable, Equatable, Sendable {
    /// The physical cameras the presenter chose, most preferred first; Darkfield Camera uses the
    /// first one connected. Names are kept so the panel can name a camera while it is unplugged.
    public var preferred: [CameraInfo] = []
    public var blur = true
    /// 0…1, mapped to a radius by `BlurScale`.
    public var blurStrength: Double = 0.7
    public var framing = true
    /// 0 frames wide around the presenter, 1 tight.
    public var framingTightness: Double = 0.5
    /// Flips the panel's preview like a mirror. A call always gets the unflipped picture.
    public var mirrorPreview = true

    public init(preferred: [CameraInfo] = [], blur: Bool = true,
                blurStrength: Double = 0.7, framing: Bool = true, framingTightness: Double = 0.5) {
        self.preferred = preferred
        self.blur = blur
        self.blurStrength = blurStrength
        self.framing = framing
        self.framingTightness = framingTightness
    }

    private enum CodingKeys: String, CodingKey {
        case preferred, blur, blurStrength, framing, framingTightness, mirrorPreview
    }

    /// Settings saved with a single chosen camera, read so that camera becomes the first preference.
    private enum SingleCameraKeys: String, CodingKey { case deviceID, deviceName }

    /// Field by field, like `Settings`: a missing or undecodable key takes its default.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func field<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        if c.contains(.preferred) {
            preferred = field(.preferred, preferred)
        } else if let single = try? decoder.container(keyedBy: SingleCameraKeys.self),
                  let id = try? single.decodeIfPresent(String.self, forKey: .deviceID) {
            let name = (try? single.decodeIfPresent(String.self, forKey: .deviceName)) ?? nil
            preferred = [CameraInfo(id: id, name: name ?? "The chosen camera")]
        }
        blur = field(.blur, blur)
        blurStrength = field(.blurStrength, blurStrength)
        framing = field(.framing, framing)
        framingTightness = field(.framingTightness, framingTightness)
        mirrorPreview = field(.mirrorPreview, mirrorPreview)
    }
}

/// The background blur's Gaussian radius, in output pixels. The top end is about three times
/// macOS Portrait's blur, comparable to Google Meet's.
public enum BlurScale {
    public static func radius(strength: Double, height: Double) -> Double {
        let s = min(max(strength, 0), 1)
        return height * (0.02 + 0.04 * s)
    }
}

/// When the camera extension stops repeating darkfield's last frame and shows dark instead: a
/// camera that went away, or darkfield quitting, must not leave the call on a frozen picture.
public enum IdleFrame {
    public static let staleAfter: TimeInterval = 0.5

    public static func isStale(lastSinkFrame: Date?, now: Date) -> Bool {
        guard let last = lastSinkFrame else { return true }
        return now.timeIntervalSince(last) > staleAfter
    }
}
