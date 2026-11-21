import Carbon
import Cocoa

/// System-wide keyboard shortcuts that work no matter which app is in front.
/// Uses Carbon's RegisterEventHotKey, which needs no Accessibility permission.
enum HotKeys {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var refs: [EventHotKeyRef] = []
    private static var installed = false

    /// Key codes for the letters we use (US layout positions).
    enum Key: UInt32 { case c = 8, l = 37, r = 15, p = 35 }

    /// ⌃⌘ + key.
    static func controlCommand(_ key: Key, _ handler: @escaping () -> Void) {
        register(key.rawValue, modifiers: UInt32(controlKey | cmdKey), handler)
    }

    static func register(_ keyCode: UInt32, modifiers: UInt32, _ handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        let id = UInt32(handlers.count + 1)
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5249_434B), id: id)   // 'RICK'
        if RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            refs.append(ref)
        } else {
            NSLog("Rick: couldn't register hotkey \(keyCode) (already taken by another app?)")
        }
    }

    private static func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            DispatchQueue.main.async { HotKeys.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
