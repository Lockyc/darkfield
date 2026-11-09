import Foundation

/// A global hotkey: Carbon virtual key code plus Carbon modifier mask (`cmdKey` 0x100,
/// `shiftKey` 0x200, `optionKey` 0x800, `controlKey` 0x1000), with its glyphs for display.
public struct HotKeySpec: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var display: String

    public init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    /// ⇧⌘1 (kVK_ANSI_1, 18), Screegle's window toggle, which darkfield replaces.
    public static let defaultWindowToggle = HotKeySpec(keyCode: 18, modifiers: 0x300, display: "⇧⌘1")
}
