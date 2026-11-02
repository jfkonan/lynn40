import Foundation

/// Raccourci global (SPEC §3) : une touche seule à maintenir, ou une combinaison.
enum HotkeyChoice: String, CaseIterable, Identifiable {
    /// Touche Fn (🌐) seule. Demande l'autorisation Accessibilité.
    case fn
    /// ⌥Espace, via Carbon : aucune autorisation nécessaire.
    case optionSpace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fn: return "Fn (🌐)"
        case .optionSpace: return "⌥ Espace"
        }
    }

    /// Nom court pour les messages (« maintenez Fn… »).
    var keyName: String {
        switch self {
        case .fn: return "Fn"
        case .optionSpace: return "⌥Espace"
        }
    }
}

enum HotkeyMode: String, CaseIterable, Identifiable {
    /// Maintenir pour parler, relâcher pour transcrire.
    case hold
    /// Un appui démarre, un appui arrête.
    case toggle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hold: return "Maintenir pour parler"
        case .toggle: return "Appuyer pour démarrer, appuyer pour arrêter"
        }
    }
}

/// Réglages propres au Mac. Les réglages communs (modèle, langue, vocabulaire, nettoyage)
/// restent dans SharedStore ; sur Mac, les deux utilisent UserDefaults.standard.
struct MacSettings {
    enum Key {
        static let hotkey = "dictee.settings.hotkey"
        static let hotkeyMode = "dictee.settings.hotkeyMode"
        static let soundsEnabled = "dictee.settings.soundsEnabled"
        static let restoreClipboard = "dictee.settings.restoreClipboard"
        /// Lu par @AppStorage dans SettingsView ; l'état réel est celui de SMAppService (voir LoginItem).
        static let launchAtLogin = "dictee.settings.launchAtLogin"
    }

    enum Default {
        static let hotkey = HotkeyChoice.fn
        static let hotkeyMode = HotkeyMode.hold
        static let soundsEnabled = true
        static let restoreClipboard = true
        static let launchAtLogin = false
    }

    let defaults: UserDefaults

    /// `defaults` est injectable pour les tests.
    init(defaults: UserDefaults = SharedStore.shared.defaults) {
        self.defaults = defaults
    }

    var hotkey: HotkeyChoice {
        get { defaults.string(forKey: Key.hotkey).flatMap(HotkeyChoice.init(rawValue:)) ?? Default.hotkey }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.hotkey) }
    }

    var hotkeyMode: HotkeyMode {
        get { defaults.string(forKey: Key.hotkeyMode).flatMap(HotkeyMode.init(rawValue:)) ?? Default.hotkeyMode }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.hotkeyMode) }
    }

    var soundsEnabled: Bool {
        get { defaults.object(forKey: Key.soundsEnabled) as? Bool ?? Default.soundsEnabled }
        nonmutating set { defaults.set(newValue, forKey: Key.soundsEnabled) }
    }

    var restoreClipboard: Bool {
        get { defaults.object(forKey: Key.restoreClipboard) as? Bool ?? Default.restoreClipboard }
        nonmutating set { defaults.set(newValue, forKey: Key.restoreClipboard) }
    }

    /// Consigne affichée dans le menu, ex. « maintenez Fn pour dicter ».
    var usageHint: String {
        switch hotkeyMode {
        case .hold: return "maintenez \(hotkey.keyName) pour dicter"
        case .toggle: return "appuyez sur \(hotkey.keyName) pour dicter"
        }
    }
}
