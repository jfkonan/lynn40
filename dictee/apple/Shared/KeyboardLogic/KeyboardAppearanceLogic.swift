import Foundation

/// Mode d'affichage du clavier (SPEC §9 : « couleurs claires et sombres d'iOS »), logique pure et testable.
/// Le champ a priorité quand il impose une apparence (`keyboardAppearance` clair ou sombre, comme le clavier
/// d'iOS) ; sinon le clavier suit le système.
enum KeyboardAppearanceLogic {
    enum Scheme: Equatable {
        case light
        case dark
    }

    /// Apparence demandée par le champ (`UITextDocumentProxy.keyboardAppearance`).
    enum FieldAppearance: Equatable {
        case light
        case dark
        case unspecified
    }

    static func scheme(field: FieldAppearance, systemIsDark: Bool) -> Scheme {
        switch field {
        case .dark: return .dark
        case .light: return .light
        case .unspecified: return systemIsDark ? .dark : .light
        }
    }
}
