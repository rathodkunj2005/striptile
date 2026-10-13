import Carbon.HIToolbox

final class HotKeys {
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false

    func register(_ bindings: [(binding: KeyBinding, action: () -> Void)]) {
        installHandler()
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
        for (index, entry) in bindings.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(entry.binding.keyCode), entry.binding.modifiers,
                                             EventHotKeyID(signature: OSType(0x5354524C), id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status != noErr { Log.write("hotkey \(entry.binding.display) failed status=\(status)") }
            if let ref { refs.append(ref) }
            actions[id] = entry.action
        }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let keys = Unmanaged<HotKeys>.fromOpaque(userData!).takeUnretainedValue()
            keys.actions[hotKeyID.id]?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
}
