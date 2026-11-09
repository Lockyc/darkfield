import AppKit
import DarkfieldCore

/// The sound the hotkey makes: Tink when a window is shared, Pop when it is unshared, the alert
/// sound when there is no window under the cursor to share.
@MainActor
enum ToggleFeedback {
    static func play(_ result: ToggleResult?) {
        switch result {
        case .added: NSSound(named: "Tink")?.play()
        case .removed: NSSound(named: "Pop")?.play()
        case .refusedOwnWindow, nil: NSSound.beep()
        }
    }
}
