import AppKit

/// Drawn over the share window while it is shown for a window picker: the canvas dimmed, with
/// the window's name and what to do. It is removed when the picker closes, which is when the
/// meeting app's capture request completes and before it sends any frame.
final class PickingOverlay: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        autoresizingMask = [.width, .height]

        let title = NSTextField(labelWithString: OutputController.meetingTitle)
        title.font = .systemFont(ofSize: 96, weight: .semibold)
        title.textColor = .white
        let hint = NSTextField(labelWithString: "Choose this window to present it")
        hint.font = .systemFont(ofSize: 36, weight: .regular)
        hint.textColor = NSColor.white.withAlphaComponent(0.7)
        let stack = NSStackView(views: [title, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
