import AppKit
import DarkfieldCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let windowToggleID: UInt32 = 1
    static let pointerToggleID: UInt32 = 2

    let canvas = CanvasModel()
    lazy var captures = CaptureManager(model: canvas)
    lazy var model = AppModel(settings: Settings.load(from: .standard), captures: captures, canvas: canvas)
    private let hotKeys = HotKeys()
    private let pointerInput = PointerInput()
    private var pointerState = PointerState()
    private var tick: Timer?
    private var drawnPointer: CGPoint?
    private var cursorReadAt: CFTimeInterval = 0
    private var statusItem: StatusItem?
    private var settingsWindow: NSWindow?
    private lazy var outputs = OutputController(canvas: canvas)
    private lazy var rings = ShareRings { [weak self] in self?.captures.set.ids ?? [] }

    private var settings: DarkfieldCore.Settings { model.settings }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        captures.settings = settings
        registerHotKeys()
        hotKeys.onPress = { [weak self] id in self?.hotKey(id) }
        model.onSettings = { [weak self] old in self?.apply(old: old) }
        model.onRecording = { [weak self] recording in
            guard let self else { return }
            if recording {
                hotKeys.set(nil, id: Self.windowToggleID)
                hotKeys.set(nil, id: Self.pointerToggleID)
            } else {
                registerHotKeys()
            }
        }
        captures.onChange = { [weak self] in
            self?.model.refreshRows()
            self?.rings.update()
        }
        captures.ignoredWindows = { [weak self] in self?.rings.windowIDs ?? [] }
        captures.start()
        startPointer()
        model.updater = Updater.make()
        statusItem = StatusItem(model: model, openSettings: { [weak self] in self?.showSettings() })
        outputs.onFallback = { [weak self] message in
            guard let self else { return }
            model.settings.output = .meeting
            model.notice = message
        }
        outputs.apply(settings.output)
    }

    /// Opening darkfield while it runs (Spotlight, Finder, the Dock) brings back its output and its
    /// Settings window, so it stays reachable without the menu-bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        outputs.apply(settings.output)
        showSettings()
        return false
    }

    /// Registers both hotkeys and records which ones macOS refused, so Settings and the panel can
    /// say so instead of a shortcut silently doing nothing.
    private func registerHotKeys() {
        var refused: Set<UInt32> = []
        if !hotKeys.set(settings.windowHotKey, id: Self.windowToggleID) { refused.insert(Self.windowToggleID) }
        if !hotKeys.set(settings.pointerHotKey, id: Self.pointerToggleID) { refused.insert(Self.pointerToggleID) }
        model.windowHotKeyRefused = refused.contains(Self.windowToggleID)
        model.pointerHotKeyRefused = refused.contains(Self.pointerToggleID)
    }

    private func apply(old: DarkfieldCore.Settings) {
        settings.save(to: .standard)
        captures.settings = settings
        if old.output != settings.output, outputs.current != settings.output {
            model.notice = nil
            outputs.apply(settings.output)
        }
        if old.windowHotKey != settings.windowHotKey || old.pointerHotKey != settings.pointerHotKey, !model.recordingHotKey {
            registerHotKeys()
        }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "darkfield Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        settingsWindow?.center()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func hotKey(_ id: UInt32) {
        switch id {
        case Self.windowToggleID:
            let p = ScreenSpace.toCG(NSEvent.mouseLocation, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
            Task { ToggleFeedback.play(await captures.toggleWindow(at: p)) }
        case Self.pointerToggleID:
            model.settings.pointerEnabled.toggle()
        default:
            break
        }
    }

    private func startPointer() {
        pointerInput.start(onMove: { [weak self] p in
            guard let self else { return }
            outputs.keepCursorOff(p)
            pointerState.moved(to: p, at: CACurrentMediaTime())
        }, onClick: { [weak self] kind, p in
            guard let self, settings.pointerEnabled,
                  let at = PointerMap.canvasPoint(p, placed: canvas.placed, onScreen: captures.onScreen) else { return }
            canvas.ripples.append(Ripple(at: at, kind: kind, start: CACurrentMediaTime()))
        })
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    /// Advances fade, spotlight and ripples; redraws only while something is visible or changing.
    private func tickPointer() {
        let now = CACurrentMediaTime()
        // Hit-tested every frame, not only on mouse moves, so the pointer is right as soon as a
        // window under a still mouse is shared, moved or uncovered.
        let mouse = ScreenSpace.toCG(NSEvent.mouseLocation, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        let hit = PointerMap.hit(mouse, placed: canvas.placed, onScreen: captures.onScreen)
        canvas.pointer = hit?.point
        if let hit {
            // Never smaller than a normal cursor on a 1080p screen, however far the window is
            // scaled down to fit.
            canvas.cursorScale = max(hit.scale, 1)
            // The system cursor's shape changes with what it's over (arrow, I-beam, hand); re-read
            // it a few times a second while it's over a shared window.
            if now - cursorReadAt > 0.1 {
                cursorReadAt = now
                canvas.cursor = Self.systemCursor() ?? canvas.cursor
            }
        }
        let opacity = settings.pointerEnabled ? pointerState.opacity(at: now, idleFade: settings.idleFade) : 0
        let scale = pointerState.spotlightScale(at: now)
        let ripples = canvas.ripples.filter { now - $0.start < Ripple.duration }
        let animating = !ripples.isEmpty || !canvas.ripples.isEmpty || (canvas.pointer != nil && opacity > 0)
        let moved = canvas.pointer != drawnPointer || settings.pointerEnabled != canvas.showCursor
        guard animating || moved || opacity != canvas.pointerOpacity || scale != canvas.pointerScale else { return }
        canvas.pointerOpacity = opacity
        canvas.pointerScale = scale
        canvas.showCursor = settings.pointerEnabled
        canvas.ripples = ripples
        drawnPointer = canvas.pointer
        canvas.changed()
    }

    /// The system's current cursor (whichever app set it) as an image with its size and hot spot
    /// in points.
    private static func systemCursor() -> (image: CGImage, size: CGSize, hotSpot: CGPoint)? {
        guard let cursor = NSCursor.currentSystem else { return nil }
        var rect = NSRect(origin: .zero, size: cursor.image.size)
        guard let image = cursor.image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return (image, cursor.image.size, cursor.hotSpot)
    }
}
