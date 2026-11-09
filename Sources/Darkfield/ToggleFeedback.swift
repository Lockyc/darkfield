import AppKit
import DarkfieldCore

/// The sound the hotkey makes: Glass when a window is shared, Bottle when it is unshared, the
/// alert sound when there is no window under the cursor to share.
@MainActor
enum ToggleFeedback {
    static func play(_ result: ToggleResult?) {
        switch result {
        case .added: NSSound(named: "Glass")?.play()
        case .removed: NSSound(named: "Bottle")?.play()
        case .refusedOwnWindow, nil: NSSound.beep()
        }
    }
}
