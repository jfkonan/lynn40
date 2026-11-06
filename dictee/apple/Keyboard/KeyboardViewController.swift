import SwiftUI
import UIKit

/// Vue d'entrée du clavier. `UIInputViewAudioFeedback` autorise le clic clavier système
/// (`UIDevice.current.playInputClick()`), si l'utilisateur l'a activé dans Réglages > Sons.
final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

/// Point d'entrée de l'extension clavier (déclaré dans NSExtensionPrincipalClass).
final class KeyboardViewController: UIInputViewController {
    /// Hauteur du clavier (barre supérieure + 4 rangées), portrait et paysage.
    static let regularHeight: CGFloat = 290
    static let compactHeight: CGFloat = 220

    private lazy var model = KeyboardModel(controller: self)
    private lazy var typing = TypingModel(controller: self)
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?

    override func loadView() {
        view = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let host = UIHostingController(rootView: KeyboardRootView(model: model, typing: typing))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        hostingController = host
        observeUserInterfaceStyle()

        let height = view.heightAnchor.constraint(equalToConstant: Self.regularHeight)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateAppearance()
        model.appear()
        typing.appear()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // `needsInputModeSwitchKey` n'est fiable qu'une fois le clavier affiché.
        typing.updateTraits()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.disappear()
        typing.disappear()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Paysage sur iPhone : clavier moins haut.
        let target = traitCollection.verticalSizeClass == .compact ? Self.compactHeight : Self.regularHeight
        if let heightConstraint, heightConstraint.constant != target {
            heightConstraint.constant = target
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateAppearance()
        typing.documentChanged()
    }

    // MARK: - Actions appelées par les modèles

    func insert(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    /// Insère une dictée au curseur. Renvoie `false` si le clavier n'est pas attaché à un champ (vue hors écran) :
    /// `insertText` serait alors perdu sans erreur.
    @discardableResult
    func insertDictation(_ text: String) -> Bool {
        guard isViewLoaded, view.window != nil else { return false }
        let toInsert = TextJoiner.textToInsert(text, before: textDocumentProxy.documentContextBeforeInput)
        guard !toInsert.isEmpty else { return true }
        textDocumentProxy.insertText(toInsert)
        typing.documentChanged()
        return true
    }

    func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    func playClick() {
        UIDevice.current.playInputClick()
    }

    /// Texte avant le curseur (majuscule automatique, double espace).
    var contextBeforeInput: String? {
        textDocumentProxy.documentContextBeforeInput
    }

    /// `autocapitalizationType` du champ ; non renseigné → phrases (comportement par défaut d'iOS).
    var autoCapitalizationMode: AutoCapitalizationMode {
        let type: UITextAutocapitalizationType? = textDocumentProxy.autocapitalizationType
        guard let type else { return .sentences }
        switch type {
        case .none: return AutoCapitalizationMode.none
        case .words: return .words
        case .sentences: return .sentences
        case .allCharacters: return .allCharacters
        @unknown default: return .sentences
        }
    }

    /// `returnKeyType` du champ, pour le libellé de ⏎.
    var returnKeyKind: ReturnKeyKind {
        let type: UIReturnKeyType? = textDocumentProxy.returnKeyType
        guard let type else { return .standard }
        switch type {
        case .default: return .standard
        case .go: return .go
        case .google: return .google
        case .join: return .join
        case .next: return .next
        case .route: return .route
        case .search: return .search
        case .send: return .send
        case .yahoo: return .yahoo
        case .done: return .done
        case .emergencyCall: return .emergencyCall
        case .continue: return .continueAction
        @unknown default: return .standard
        }
    }

    /// 🌐 : toucher = clavier suivant, appui long = liste des claviers (API prévue pour les claviers tiers).
    func attachInputModeSwitch(to control: UIControl) {
        control.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
    }

    /// Ouvre l'app Dictée. Les claviers n'ont pas d'API officielle pour ça : on remonte la chaîne
    /// des répondeurs jusqu'à UIApplication et on appelle `openURL:options:completionHandler:`
    /// via le runtime Objective-C. Technique répandue (Wispr Flow, SuperWhisper…) mais non documentée.
    @discardableResult
    func openContainingApp(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication, application.responds(to: selector) {
                typealias OpenURLFunction = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let implementation = application.method(for: selector)
                let open = unsafeBitCast(implementation, to: OpenURLFunction.self)
                open(application, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    // MARK: - Apparence

    /// Mode clair ou sombre : celui imposé par le champ (`keyboardAppearance`), sinon celui du système
    /// (`KeyboardAppearanceLogic`). Poussé explicitement dans l'environnement SwiftUI : dans une extension clavier,
    /// le mode du système ne se propage pas toujours de lui-même à la vue hébergée. La trait collection du
    /// contrôleur n'est jamais forcée, pour qu'elle reflète toujours le système.
    private func updateAppearance() {
        let field: KeyboardAppearanceLogic.FieldAppearance
        switch textDocumentProxy.keyboardAppearance {
        case .some(.dark): field = .dark
        case .some(.light): field = .light
        default: field = .unspecified
        }
        let systemIsDark = traitCollection.userInterfaceStyle == .dark
        switch KeyboardAppearanceLogic.scheme(field: field, systemIsDark: systemIsDark) {
        case .dark: model.setColorScheme(.dark)
        case .light: model.setColorScheme(.light)
        }
    }

    /// Basculement clair/sombre du système pendant que le clavier est affiché.
    private func observeUserInterfaceStyle() {
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
                self.updateAppearance()
            }
        }
    }

    /// Repli pour iOS 16 ; à partir d'iOS 17, `registerForTraitChanges` prend le relais.
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            updateAppearance()
        }
    }
}
