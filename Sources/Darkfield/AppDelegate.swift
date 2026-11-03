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
    private var statusItem: StatusItem?
    private var settingsWindow: NSWindow?
    private lazy var outputs = OutputController(canvas: canvas)

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
        captures.onChange = { [weak self] in self?.model.refreshRows() }
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
            guard let app = NSWorkspace.shared.frontmostApplication else { return }
            Task { await captures.toggleFrontWindow(of: app) }
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
            canvas.pointer = PointerMap.canvasPoint(p, placed: canvas.placed, onScreen: captures.onScreen)
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
        let opacity = settings.pointerEnabled ? pointerState.opacity(at: now, idleFade: settings.idleFade) : 0
        let scale = pointerState.spotlightScale(at: now)
        let ripples = canvas.ripples.filter { now - $0.start < Ripple.duration }
        let animating = !ripples.isEmpty || !canvas.ripples.isEmpty || (canvas.pointer != nil && opacity > 0)
        guard animating || opacity != canvas.pointerOpacity || scale != canvas.pointerScale else { return }
        canvas.pointerOpacity = opacity
        canvas.pointerScale = scale
        canvas.ripples = ripples
        canvas.changed()
    }
}
