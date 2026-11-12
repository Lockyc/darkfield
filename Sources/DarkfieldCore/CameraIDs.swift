import Foundation

/// The identity darkfield and its camera extension share. The UUIDs are fixed: a video app
/// remembers the camera it last used by device id.
public enum CameraIDs {
    public static let deviceName = "Darkfield Camera"
    public static let device = UUID(uuidString: "6D0C5B4E-1F8A-4E43-9B1C-2C7A9B3E5D10")!
    /// The stream video apps read.
    public static let sourceStream = UUID(uuidString: "6D0C5B4E-1F8A-4E43-9B1C-2C7A9B3E5D11")!
    /// The stream darkfield writes its processed frames into.
    public static let sinkStream = UUID(uuidString: "6D0C5B4E-1F8A-4E43-9B1C-2C7A9B3E5D12")!
    /// A custom property on the source stream: "1" while any app is streaming from Darkfield
    /// Camera, else "0". darkfield runs the physical camera only while it reads "1".
    public static let clientsProperty = "4cc_dfcl_glob_0000"
    /// The same property's selector, as darkfield reads it through CoreMediaIO.
    public static let clientsSelector: UInt32 = 0x6466_636C // 'dfcl'
    public static let width = 1920
    public static let height = 1080
    public static let frameRate = 30
}
