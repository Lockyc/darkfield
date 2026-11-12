import AppKit
import ApplicationServices
import DarkfieldCore
import ScreenCaptureKit

/// Resizes another app's window through Accessibility so the canvas shows it at 1:1
/// (`Layout.unscaledFrame`). Needs the Accessibility grant; the first press without it asks.
@MainActor
enum WindowFitter {
    /// false when there's nothing to resize or darkfield isn't trusted; the caller beeps.
    static func fit(_ window: SCWindow, margin: CGFloat) -> Bool {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        guard AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary),
              let pid = window.owningApplication?.processID,
              let ax = element(for: window, pid: pid),
              let screen = WindowCapture.screen(for: window.frame) else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let visible = ScreenSpace.toCG(screen.visibleFrame, primaryHeight: primaryHeight)
        let target = Layout.unscaledFrame(for: window.frame, margin: margin, visible: visible)
        // Size, move, size: an app can refuse a size that would overhang the screen at the old
        // position, then accept it once the window has moved.
        set(ax, kAXSizeAttribute, target.size)
        set(ax, kAXPositionAttribute, target.origin)
        set(ax, kAXSizeAttribute, target.size)
        return true
    }

    /// The owning app's Accessibility window whose frame is `window`'s (both CG global).
    private static func element(for window: SCWindow, pid: pid_t) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { frame(of: $0).map { close($0, window.frame) } ?? false }
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &p)
        AXValueGetValue(size as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1 && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
    }

    private static func set(_ element: AXUIElement, _ attribute: String, _ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(element, attribute as CFString, v) }
    }

    private static func set(_ element: AXUIElement, _ attribute: String, _ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(element, attribute as CFString, v) }
    }
}
