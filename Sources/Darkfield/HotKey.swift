import Carbon.HIToolbox
import DarkfieldCore

/// System-wide hotkeys via Carbon `RegisterEventHotKey`: they fire whatever app is frontmost.
/// Each registration has an id; `onPress` receives it.
@MainActor
final class HotKeys {
    var onPress: ((UInt32) -> Void)?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let me = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            let id = hk.id
            MainActor.assumeIsolated { me.onPress?(id) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Registers `spec` under `id`, replacing any earlier registration of that id; nil unregisters.
    /// false when macOS refuses the combination.
    @discardableResult
    func set(_ spec: HotKeySpec?, id: UInt32) -> Bool {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        guard let spec else { return true }
        var ref: EventHotKeyRef?
        let hk = EventHotKeyID(signature: OSType(0x5052_5321), id: id) // 'PRS!'
        guard RegisterEventHotKey(spec.keyCode, spec.modifiers, hk, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else { return false }
        refs[id] = ref
        return true
    }
}
