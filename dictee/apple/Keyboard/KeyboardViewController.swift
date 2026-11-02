import SwiftUI
import UIKit

/// Point d'entrée de l'extension clavier (déclaré dans NSExtensionPrincipalClass).
final class KeyboardViewController: UIInputViewController {
    private lazy var model = KeyboardModel(controller: self)
    private var hostingController: UIHostingController<KeyboardView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let host = UIHostingController(rootView: KeyboardView(model: model))
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

        let height = view.heightAnchor.constraint(equalToConstant: 270)
        height.priority = UILayoutPriority(999)
        height.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.appear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.disappear()
    }

    // MARK: - Actions appelées par le modèle

    func insert(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    func insertDictation(_ text: String) {
        let toInsert = TextJoiner.textToInsert(text, before: textDocumentProxy.documentContextBeforeInput)
        guard !toInsert.isEmpty else { return }
        textDocumentProxy.insertText(toInsert)
    }

    func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    var showsGlobeKey: Bool { needsInputModeSwitchKey }

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
}
