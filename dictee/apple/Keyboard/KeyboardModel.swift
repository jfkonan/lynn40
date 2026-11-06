import Foundation
import SwiftUI

/// Session de dictée et barre supérieure du clavier : suit l'état de l'app via l'App Group, pilote la dictée
/// par signaux Darwin, et gère la pastille de style et le panneau rapide (SPEC §9).
@MainActor
final class KeyboardModel: ObservableObject {
    enum Phase: Equatable {
        case noFullAccess
        case needsSession
        case ready
        case recording
        case transcribing
        case error(String)
    }

    /// Message affiché dans la barre supérieure à la place de la pastille (aide ou erreur).
    struct Message: Equatable {
        let text: String
        let isError: Bool
    }

    /// Choix de langue du panneau rapide (liste commune `DictationLanguage`), plus la langue réglée dans l'app
    /// si elle est autre (ex. `es`).
    var languageChoices: [DictationLanguage] { DictationLanguage.choices(including: language) }

    /// Mode clair ou sombre poussé dans l'environnement SwiftUI, réglé par `KeyboardViewController`
    /// (champ puis système, voir `KeyboardAppearanceLogic`).
    @Published private(set) var colorScheme: ColorScheme = .light
    @Published private(set) var phase: Phase = .needsSession
    @Published private(set) var hint: String?
    @Published private(set) var style: WritingStyle = SharedStore.Default.writingStyle
    @Published private(set) var provider: TranscriptionProvider = .openai
    @Published private(set) var language: String = SharedStore.Default.language
    @Published private(set) var history: [Transcript] = []
    @Published private(set) var panelOpen = false
    @Published private(set) var styleMenuOpen = false
    /// Erreur masquée par l'utilisateur (toucher sur le message) : elle ne réapparaît qu'à la dictée suivante.
    @Published private var dismissedError: String?

    private weak var controller: KeyboardViewController?
    private let store = SharedStore.shared
    private var tokens: [UUID] = []
    private var refreshTimer: Timer?
    private var startTimeout: DispatchWorkItem?
    private var transcriptRetry: DispatchWorkItem?

    init(controller: KeyboardViewController) {
        self.controller = controller
    }

    func setColorScheme(_ scheme: ColorScheme) {
        guard colorScheme != scheme else { return }
        colorScheme = scheme
    }

    deinit {
        let notifier = DarwinNotifier.shared
        tokens.forEach { notifier.remove($0) }
    }

    // MARK: - Cycle de vie

    func appear() {
        if tokens.isEmpty {
            let notifier = DarwinNotifier.shared
            tokens = [
                notifier.observe(.stateChanged) { [weak self] in self?.stateChanged() },
                notifier.observe(.transcriptReady) { [weak self] in self?.transcriptReady() },
            ]
        }
        refreshTimer?.invalidate()
        // Seule minuterie du clavier : détecte une session arrêtée sans signal (app tuée). Arrêtée à la disparition.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        loadSettings()
        refresh()
        // Si une transcription est arrivée pendant que le clavier était masqué (récente uniquement).
        insertPendingTranscript()
    }

    func disappear() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        transcriptRetry?.cancel()
        transcriptRetry = nil
        if phase == .recording {
            DarwinNotifier.shared.post(.cancelRecording)
        }
        if styleMenuOpen { styleMenuOpen = false }
        if panelOpen { panelOpen = false }
    }

    // MARK: - Micro

    func micTapped() {
        refresh()
        styleMenuOpen = false
        switch phase {
        case .noFullAccess:
            showFullAccessHint()
        case .needsSession:
            openApp()
        case .ready, .error:
            hint = nil
            dismissedError = nil
            phase = .recording
            DarwinNotifier.shared.post(.startRecording)
            armStartTimeout()
        case .recording:
            phase = .transcribing
            DarwinNotifier.shared.post(.stopRecording)
        case .transcribing:
            break
        }
    }

    /// Appui long sur le micro : annule l'écoute en cours ; sinon, se comporte comme un toucher.
    func micLongPressed() {
        if phase == .recording {
            cancelTapped()
        } else {
            micTapped()
        }
    }

    func cancelTapped() {
        DarwinNotifier.shared.post(.cancelRecording)
    }

    /// Action VoiceOver « Annuler la dictée ».
    func cancelIfRecording() {
        if phase == .recording { cancelTapped() }
    }

    // MARK: - Barre supérieure

    /// Texte de la pastille : le style (« Brut. »), ou l'état pendant la dictée.
    var chipText: String {
        switch phase {
        case .recording: return "Écoute…"
        case .transcribing: return "Transcription…"
        default: return style.chipLabel
        }
    }

    var message: Message? {
        if let hint { return Message(text: hint, isError: false) }
        if case let .error(text) = phase, text != dismissedError { return Message(text: text, isError: true) }
        return nil
    }

    func dismissMessage() {
        if hint != nil {
            hint = nil
        } else if case let .error(text) = phase {
            dismissedError = text
        }
    }

    func toggleStyleMenu() {
        styleMenuOpen.toggle()
    }

    func closeStyleMenu() {
        if styleMenuOpen { styleMenuOpen = false }
    }

    // MARK: - Panneau rapide

    func togglePanel() {
        if panelOpen {
            closePanel()
        } else {
            styleMenuOpen = false
            loadSettings()
            history = store.history
            panelOpen = true
            controller?.refreshPredictions()
        }
    }

    func closePanel() {
        guard panelOpen else { return }
        panelOpen = false
        controller?.refreshPredictions()
    }

    /// Réglages écrits dans l'App Group (mêmes clés que l'app), pris en compte à la dictée suivante.
    func selectStyle(_ newStyle: WritingStyle) {
        styleMenuOpen = false
        guard ensureFullAccess() else { return }
        store.writingStyle = newStyle
        style = newStyle
    }

    func selectProvider(_ newProvider: TranscriptionProvider) {
        guard ensureFullAccess() else { return }
        store.provider = newProvider
        provider = newProvider
    }

    func selectLanguage(_ code: String) {
        guard ensureFullAccess() else { return }
        store.language = code
        language = code
    }

    func insertFromHistory(_ transcript: Transcript) {
        controller?.insertDictation(transcript.text)
        closePanel()
    }

    func clearHistory() {
        guard ensureFullAccess() else { return }
        store.clearHistory()
        history = []
    }

    /// « Ouvrir Dictée » : ouvre l'app sur ses réglages (`dictee://settings`).
    func openDicteeSettings() {
        guard let url = URL(string: "dictee://settings"), controller?.openContainingApp(url) == true else {
            hint = "Ouvrez l'app Dictée depuis l'écran d'accueil."
            return
        }
        closePanel()
    }

    // MARK: - Synchronisation avec l'app

    func refresh() {
        guard let controller else { return }
        let storedStyle = store.writingStyle
        if storedStyle != style { style = storedStyle }

        guard controller.hasFullAccess else {
            setPhase(.noFullAccess)
            return
        }
        guard store.isSessionAlive() else {
            // L'app peut finir une transcription même après la fin de session.
            setPhase(store.state == .transcribing ? .transcribing : .needsSession)
            return
        }
        switch store.state {
        case .idle:
            if phase != .recording || startTimeout == nil { setPhase(.ready) }
        case .recording:
            startTimeout?.cancel()
            startTimeout = nil
            setPhase(.recording)
        case .transcribing:
            setPhase(.transcribing)
        case .error:
            if phase != .recording || startTimeout == nil {
                setPhase(.error(store.errorMessage ?? "Erreur inconnue."))
            }
        }
    }

    /// Ne publie que les changements réels (évite de redessiner le clavier chaque seconde).
    private func setPhase(_ newPhase: Phase) {
        guard newPhase != phase else { return }
        let wasWaiting = phase == .needsSession || phase == .noFullAccess
        phase = newPhase
        if wasWaiting, newPhase == .ready { hint = nil }
    }

    private func loadSettings() {
        let storedStyle = store.writingStyle
        if storedStyle != style { style = storedStyle }
        let storedProvider = store.provider
        if storedProvider != provider { provider = storedProvider }
        let storedLanguage = store.language
        if storedLanguage != language { language = storedLanguage }
    }

    /// Signal « état changé » de l'app. Quand l'app repasse à `idle` après une transcription, le texte peut déjà être
    /// disponible même si le signal `transcriptReady` a été manqué (clavier masqué à ce moment-là).
    private func stateChanged() {
        refresh()
        if store.state == .idle { insertPendingTranscript() }
    }

    /// Signal « transcription prête » de l'app. Les UserDefaults partagés entre processus peuvent être relus en
    /// retard (HANDOFF, point à risque n° 4) : si rien n'est encore lisible, on réessaie brièvement.
    private func transcriptReady() {
        if insertPendingTranscript() { return }
        scheduleTranscriptRetry(remaining: Self.transcriptRetryDelays)
    }

    static let transcriptRetryDelays: [TimeInterval] = [0.15, 0.5, 1.5]

    private func scheduleTranscriptRetry(remaining: [TimeInterval]) {
        guard let delay = remaining.first else { return }
        transcriptRetry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.transcriptRetry = nil
            if !self.insertPendingTranscript() {
                self.scheduleTranscriptRetry(remaining: Array(remaining.dropFirst()))
            }
        }
        transcriptRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Insère la dernière transcription pas encore insérée. Renvoie `true` si un texte a été inséré.
    /// Marquée consommée seulement après l'insertion : si le clavier n'est plus attaché à un champ, elle reste
    /// disponible pour la prochaine apparition (dans la limite d'âge de `unconsumedTranscript`).
    @discardableResult
    private func insertPendingTranscript() -> Bool {
        refresh()
        guard let transcript = store.unconsumedTranscript(), let controller else { return false }
        guard controller.insertDictation(transcript.text) else { return false }
        store.markConsumed(transcript)
        return true
    }

    private func ensureFullAccess() -> Bool {
        guard controller?.hasFullAccess == true else {
            showFullAccessHint()
            return false
        }
        return true
    }

    private func showFullAccessHint() {
        hint = "Activez « Autoriser l'accès complet » : Réglages > Général > Clavier > Claviers > Dictée."
    }

    private func openApp() {
        guard let url = URL(string: "dictee://start"), controller?.openContainingApp(url) == true else {
            hint = "Ouvrez l'app Dictée et touchez « Démarrer la session »."
            return
        }
        hint = "Après l'ouverture, revenez ici avec « ‹ » en haut à gauche."
    }

    /// Si l'app ne confirme pas le début d'enregistrement, c'est qu'elle ne tourne plus.
    private func armStartTimeout() {
        startTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.startTimeout = nil
            if self.store.state != .recording {
                self.phase = .needsSession
                self.hint = "L'app Dictée ne répond pas. Touchez le micro pour relancer la session."
            }
        }
        startTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
