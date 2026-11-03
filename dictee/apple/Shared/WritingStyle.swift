import Foundation

/// Style d'écriture appliqué au nettoyage (SPEC §2, « Style d'écriture », et §3 `writingStyle`).
/// La valeur brute est celle stockée dans UserDefaults (`dictee.settings.writingStyle`).
/// Les consignes envoyées au modèle sont dans `Core/OpenAIClient.swift` (`cleanupInstruction`) : le clavier n'en a pas besoin.
enum WritingStyle: String, CaseIterable, Identifiable, Sendable {
    case brut
    case formel
    case courriel
    case decontracte

    var id: String { rawValue }

    /// Valeur du réglage : vide, absente ou inconnue → `brut` (SPEC §3).
    /// Comparaison exacte, comme `@AppStorage`, pour que l'interface et la dictée voient le même style.
    init(storedValue: String?) {
        self = storedValue.flatMap { WritingStyle(rawValue: $0) } ?? .brut
    }

    /// Libellé de l'interface : « Brut », « Formel », « Courriel », « Décontracté ».
    var label: String {
        switch self {
        case .brut: return "Brut"
        case .formel: return "Formel"
        case .courriel: return "Courriel"
        case .decontracte: return "Décontracté"
        }
    }

    /// Libellé de la pastille du clavier : le style suivi d'un point (« Brut. », « Formel. »…), SPEC §9.
    var chipLabel: String { label + "." }
}
