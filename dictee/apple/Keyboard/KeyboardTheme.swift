import SwiftUI
import UIKit

/// Couleurs du clavier, proches de celles d'iOS en mode clair et sombre.
/// Couleurs dynamiques (`UIColor` à fournisseur) : elles suivent `userInterfaceStyle`, que
/// `KeyboardViewController` force selon `keyboardAppearance` du champ. Énumération non isolée :
/// le fournisseur de couleur n'est jamais créé dans un contexte `@MainActor`.
enum KeyboardTheme {
    /// Fond du clavier (gris clair comme sur la maquette, gris anthracite en mode sombre).
    static let background = dynamic(light: rgb(0.878, 0.882, 0.902), dark: rgb(0.169, 0.169, 0.176))
    /// Touches de lettres.
    static let key = dynamic(light: .white, dark: UIColor(white: 0.42, alpha: 1))
    /// Touches spéciales (⇧, ⌫, 123, ⏎) : blanches en mode clair, comme sur la maquette.
    static let specialKey = dynamic(light: .white, dark: UIColor(white: 0.29, alpha: 1))
    /// Touche enfoncée.
    static let keyPressed = dynamic(light: rgb(0.698, 0.718, 0.757), dark: UIColor(white: 0.56, alpha: 1))
    /// Liseré sous les touches.
    static let keyShadow = dynamic(light: UIColor(white: 0, alpha: 0.28), dark: UIColor(white: 0, alpha: 0.6))
    static let keyText = dynamic(light: .black, dark: .white)
    static let secondaryText = dynamic(light: UIColor(white: 0.38, alpha: 1), dark: UIColor(white: 0.72, alpha: 1))
    /// Pastille de style, menu des styles et cartes du panneau.
    static let chip = dynamic(light: .white, dark: UIColor(white: 0.36, alpha: 1))
    /// Bouton micro : cercle noir et icône blanche (inversés en mode sombre pour rester visibles).
    static let micBackground = dynamic(light: rgb(0.11, 0.11, 0.118), dark: UIColor(white: 0.95, alpha: 1))
    static let micIcon = dynamic(light: .white, dark: .black)
    static let micRecording = Color(uiColor: .systemRed)
    static let accent = Color(uiColor: .systemBlue)
    static let error = Color(uiColor: .systemRed)

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}
