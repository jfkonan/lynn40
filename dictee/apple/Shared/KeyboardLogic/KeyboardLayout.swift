import Foundation

// Logique pure du clavier AZERTY (SPEC §9), sans UIKit : compilée dans le clavier et dans l'app iOS
// (pour DicteeTests), exclue de l'app Mac dans project.yml.

/// Couche de touches affichée.
enum KeyboardLayer: Hashable, Sendable {
    case letters
    case numbers
    case symbols

    /// Libellé de la touche qui mène à cette couche : « ABC », « 123 », « #+= ».
    var switchLabel: String {
        switch self {
        case .letters: return "ABC"
        case .numbers: return "123"
        case .symbols: return "#+="
        }
    }
}

/// Une touche. Les caractères sont stockés en minuscules ; la majuscule est appliquée à l'affichage et à la frappe.
enum KeyboardKey: Hashable, Sendable {
    case character(String)
    case shift
    case delete
    /// Bascule vers une autre couche (« 123 », « #+= », « ABC »).
    case layer(KeyboardLayer)
    /// 🌐 : clavier suivant (seulement si `needsInputModeSwitchKey`).
    case globe
    case space
    case returnKey

    var isCharacter: Bool {
        if case .character = self { return true }
        return false
    }
}

/// Position d'une touche dans la couche courante (rangée, colonne).
struct KeyPosition: Hashable, Sendable {
    let row: Int
    let column: Int
}

/// Disposition des trois couches et largeur relative des touches.
enum KeyboardLayout {
    /// Libellé de la barre d'espace.
    static let spaceLabel = "Dictée"
    /// Chaque rangée fait 10 unités de large (10 lettres sur les deux premières rangées).
    static let rowUnits: Double = 10
    /// ⇧, ⌫ et la bascule de couche de la 3e rangée.
    static let sideKeyUnits: Double = 1.5
    /// Bascule de couche et 🌐 de la rangée du bas, et ⏎.
    static let bottomKeyUnits: Double = 2.5

    static func rows(for layer: KeyboardLayer, showsGlobe: Bool) -> [[KeyboardKey]] {
        let bottom = bottomRow(layerKey: layer == .letters ? .numbers : .letters, showsGlobe: showsGlobe)
        switch layer {
        case .letters:
            return [
                characters(["a", "z", "e", "r", "t", "y", "u", "i", "o", "p"]),
                characters(["q", "s", "d", "f", "g", "h", "j", "k", "l", "m"]),
                [.shift] + characters(["w", "x", "c", "v", "b", "n", "'"]) + [.delete],
                bottom,
            ]
        case .numbers:
            return [
                characters(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]),
                characters(["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""]),
                [.layer(.symbols)] + characters([".", ",", "?", "!", "'"]) + [.delete],
                bottom,
            ]
        case .symbols:
            return [
                characters(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]),
                characters(["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "•"]),
                [.layer(.numbers)] + characters([".", ",", "?", "!", "'"]) + [.delete],
                bottom,
            ]
        }
    }

    /// Largeur relative de chaque touche d'une rangée ; la somme vaut toujours `rowUnits`.
    /// - Rangée du bas : bascule 2,5 (1,25 si 🌐 est affiché), 🌐 1,25, ⏎ 2,5, l'espace prend le reste.
    /// - Autres rangées : ⇧, ⌫ et bascule 1,5 ; les caractères se partagent le reste à parts égales.
    static func widthUnits(for row: [KeyboardKey]) -> [Double] {
        if row.contains(.space) {
            let hasGlobe = row.contains(.globe)
            let fixed: [Double?] = row.map { (key: KeyboardKey) -> Double? in
                switch key {
                case .layer: return hasGlobe ? bottomKeyUnits / 2 : bottomKeyUnits
                case .globe: return bottomKeyUnits / 2
                case .returnKey: return bottomKeyUnits
                case .space: return nil
                default: return 1
                }
            }
            let used = fixed.compactMap { $0 }.reduce(0, +)
            let flexibleCount = Double(fixed.filter { $0 == nil }.count)
            let flexible = flexibleCount > 0 ? max(rowUnits - used, 1) / flexibleCount : 0
            return fixed.map { $0 ?? flexible }
        }
        let sideCount = Double(row.filter { !$0.isCharacter }.count)
        let characterCount = Double(row.filter { $0.isCharacter }.count)
        let characterUnits = characterCount > 0 ? (rowUnits - sideCount * sideKeyUnits) / characterCount : 0
        return row.map { $0.isCharacter ? characterUnits : sideKeyUnits }
    }

    /// Texte tapé par une touche caractère : en majuscule sur la couche lettres si ⇧ est actif.
    static func output(for character: String, layer: KeyboardLayer, shift: ShiftState) -> String {
        guard layer == .letters, shift != .off else { return character }
        return character.uppercased()
    }

    private static func characters(_ list: [String]) -> [KeyboardKey] {
        list.map { KeyboardKey.character($0) }
    }

    private static func bottomRow(layerKey: KeyboardLayer, showsGlobe: Bool) -> [KeyboardKey] {
        showsGlobe
            ? [.layer(layerKey), .globe, .space, .returnKey]
            : [.layer(layerKey), .space, .returnKey]
    }
}

/// Accents proposés par appui long (SPEC §9), dans l'ordre du cahier des charges.
enum AccentTable {
    static let lowercaseVariants: [String: [String]] = [
        "e": ["é", "è", "ê", "ë"],
        "a": ["à", "â", "æ"],
        "c": ["ç"],
        "u": ["ù", "û", "ü"],
        "i": ["î", "ï"],
        "o": ["ô", "œ"],
        "y": ["ÿ"],
    ]

    /// Variantes accentuées d'une lettre, en majuscules si la lettre est en majuscule ; vide si aucune.
    static func variants(for character: String) -> [String] {
        let lower = character.lowercased()
        guard let list = lowercaseVariants[lower] else { return [] }
        return character == lower ? list : list.map { $0.uppercased() }
    }
}
