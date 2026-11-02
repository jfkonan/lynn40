import Foundation

/// Petite surcouche à CFNotificationCenter (centre Darwin) pour envoyer et recevoir
/// des signaux entre l'app et l'extension clavier. Les gestionnaires sont appelés sur le thread principal.
final class DarwinNotifier: @unchecked Sendable {
    static let shared = DarwinNotifier()

    private let lock = NSLock()
    private var handlers: [String: [UUID: () -> Void]] = [:]
    private var registeredNames: Set<String> = []

    private init() {}

    func post(_ signal: DictationSignal) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(signal.rawValue as CFString), nil, nil, true)
    }

    /// Enregistre un gestionnaire et renvoie un jeton à passer à `remove(_:)`.
    @discardableResult
    func observe(_ signal: DictationSignal, handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        let name = signal.rawValue

        lock.lock()
        handlers[name, default: [:]][token] = handler
        let needsRegistration = !registeredNames.contains(name)
        if needsRegistration { registeredNames.insert(name) }
        lock.unlock()

        if needsRegistration {
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            let observer = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterAddObserver(
                center,
                observer,
                { _, observer, name, _, _ in
                    guard let observer, let name else { return }
                    let notifier = Unmanaged<DarwinNotifier>.fromOpaque(observer).takeUnretainedValue()
                    notifier.dispatch(name.rawValue as String)
                },
                name as CFString,
                nil,
                .deliverImmediately
            )
        }
        return token
    }

    func remove(_ token: UUID) {
        lock.lock()
        for name in handlers.keys {
            handlers[name]?[token] = nil
        }
        lock.unlock()
    }

    private func dispatch(_ name: String) {
        lock.lock()
        let current = Array((handlers[name] ?? [:]).values)
        lock.unlock()
        DispatchQueue.main.async {
            current.forEach { $0() }
        }
    }
}
