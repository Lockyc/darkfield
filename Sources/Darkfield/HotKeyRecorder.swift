import AppKit
import Carbon.HIToolbox
import DarkfieldCore
import SwiftUI

/// Records a global hotkey: click, press the combination (at least one of ⌘⌥⌃), or ⎋ to cancel.
struct HotKeyRecorder: View {
    @Binding var spec: HotKeySpec?
    @Binding var recording: Bool
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(recording ? "Press keys…" : (spec?.display ?? "None")) {
                recording ? stop() : start()
            }
            .frame(minWidth: 110)
            Button("Clear") { spec = nil }.disabled(spec == nil)
        }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer { stop() }
            if event.keyCode == UInt16(kVK_Escape) { return nil }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return nil }
            spec = HotKeySpec(keyCode: UInt32(event.keyCode), modifiers: Self.carbon(flags),
                              display: Self.glyphs(flags) + Self.keyName(event))
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    static func carbon(_ f: NSEvent.ModifierFlags) -> UInt32 {
        (f.contains(.command) ? UInt32(cmdKey) : 0) | (f.contains(.shift) ? UInt32(shiftKey) : 0)
            | (f.contains(.option) ? UInt32(optionKey) : 0) | (f.contains(.control) ? UInt32(controlKey) : 0)
    }

    static func glyphs(_ f: NSEvent.ModifierFlags) -> String {
        (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "")
            + (f.contains(.shift) ? "⇧" : "") + (f.contains(.command) ? "⌘" : "")
    }

    static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_Space: "Space", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    ]

    static func keyName(_ e: NSEvent) -> String {
        functionKeys[Int(e.keyCode)] ?? (e.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
