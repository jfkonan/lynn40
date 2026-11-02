import Carbon

/// Raccourci global enregistré via Carbon (`RegisterEventHotKey`).
/// Aucune autorisation n'est nécessaire et la touche est « consommée » : l'app au premier plan ne la reçoit pas.
/// Les événements arrivent sur le thread principal (cible d'événements de l'application).
final class CarbonHotKey {
    /// 'DCTE' : signature commune à tous les raccourcis de Dictée.
    private static let signature: OSType = 0x4443_5445

    private let hotKeyID: EventHotKeyID
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var isPressed = false

    /// Appelé à l'appui puis au relâchement (la répétition automatique est ignorée).
    var onEdge: ((HotkeyEdge) -> Void)?

    /// `id` doit être unique parmi les raccourcis de l'app.
    init(id: UInt32) {
        hotKeyID = EventHotKeyID(signature: CarbonHotKey.signature, id: id)
    }

    deinit {
        unregister()
    }

    /// `keyCode` : code virtuel (kVK_…) ; `modifiers` : masque Carbon (optionKey, cmdKey…).
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        // Le callback C ne capture rien : l'instance lui est passée via userData.
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            eventTypes.count,
            &eventTypes,
            userData,
            &handlerRef
        )
        guard installStatus == OSStatus(noErr) else {
            handlerRef = nil
            return false
        }

        var ref: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &ref
        )
        guard registerStatus == OSStatus(noErr), let ref else {
            unregister()
            return false
        }
        hotKeyRef = ref
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        isPressed = false
    }

    fileprivate func handle(receivedID: EventHotKeyID, kind: UInt32) -> OSStatus {
        // Chaque instance installe son propre gestionnaire : on laisse passer les raccourcis des autres.
        guard receivedID.signature == hotKeyID.signature, receivedID.id == hotKeyID.id else {
            return OSStatus(eventNotHandledErr)
        }
        if kind == UInt32(kEventHotKeyPressed) {
            guard !isPressed else { return OSStatus(noErr) }
            isPressed = true
            onEdge?(.pressed)
        } else if kind == UInt32(kEventHotKeyReleased) {
            guard isPressed else { return OSStatus(noErr) }
            isPressed = false
            onEdge?(.released)
        }
        return OSStatus(noErr)
    }
}

/// Gestionnaire C (sans capture, donc convertible en EventHandlerUPP).
private func carbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var receivedID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &receivedID
    )
    guard status == OSStatus(noErr) else { return status }
    let hotKey = Unmanaged<CarbonHotKey>.fromOpaque(userData).takeUnretainedValue()
    return hotKey.handle(receivedID: receivedID, kind: GetEventKind(event))
}
