import AppKit
import Combine

/// Chef d'orchestre de l'app Mac : raccourci → micro → OpenAI → insertion au curseur.
/// États (SPEC §7) : idle → recording → transcribing → idle ; `error` revient à idle à la dictée suivante.
@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()

    /// Arrêt automatique (SPEC §2.1). Pour la recette, abaisser temporairement (10 s, par exemple).
    static let maxRecordingDuration: TimeInterval = TranscriptionRules.maxRecordingDuration

    @Published private(set) var state: DictationState = .idle
    @Published private(set) var lastTranscript = ""
    @Published private(set) var lastError: String?
    @Published private(set) var accessibilityGranted = Permissions.accessibilityGranted
    /// Problème de raccourci à signaler dans les réglages (autorisation manquante, combinaison déjà prise).
    @Published private(set) var hotkeyWarning: String?

    private let store = SharedStore.shared
    private let settings = MacSettings()
    private let hotkeys: HotkeyManager
    private let capture: AudioCapture
    private let inserter: TextInserter
    /// Créée à la première utilisation : AppKit doit être prêt avant de créer une fenêtre.
    private lazy var overlay = OverlayController()

    private var started = false
    private var levelTimer: Timer?
    private var accessibilityTimer: Timer?
    private var maxDurationTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var startFeedbackTask: Task<Void, Never>?
    /// « Tink » joué pour la dictée en cours : « Pop » suivra, même pour un appui trop court.
    private var startSoundPlayed = false

    private init() {
        hotkeys = HotkeyManager()
        capture = AudioCapture()
        inserter = TextInserter()
    }

    // MARK: - Démarrage

    func start() {
        guard !started else { return }
        started = true
        Self.purgeLeftoverAudio()

        hotkeys.onEdge = { [weak self] edge in self?.handleHotkey(edge) }
        hotkeys.onEscape = { [weak self] in self?.cancel(silently: false) }
        // Fn+autre touche : raccourci système. En mode « maintenir », c'est cet appui de Fn qui avait lancé l'écoute.
        hotkeys.onFnChord = { [weak self] in
            guard let self, self.settings.hotkeyMode == .hold else { return }
            self.cancel(silently: true)
        }
        // Micro impossible à relancer après un changement de périphérique : on transcrit ce qui a déjà été dit.
        capture.onConfigurationChange = { [weak self] in self?.stop() }

        reloadHotkeys()

        // AXIsProcessTrusted n'émet aucune notification : on le relit toutes les 2 s.
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAccessibility() }
        }

        // Premier lancement : il manque la clé, ou l'autorisation nécessaire au raccourci Fn.
        let needsKey = KeychainStore.loadAPIKey() == nil
        let needsAccessibility = settings.hotkey == .fn && !accessibilityGranted
        if needsKey || needsAccessibility {
            SettingsWindowController.shared.show()
        }
    }

    /// Raccourci ou mode modifié dans les réglages. Une dictée en cours est annulée : le nouveau réglage
    /// ne saurait pas l'arrêter comme elle a commencé (relâchement attendu en « maintenir », appui en « basculer »).
    func hotkeySettingsChanged() {
        if state == .recording { cancel(silently: true) }
        reloadHotkeys()
    }

    /// Réinstalle le raccourci (changement de réglage ou autorisation Accessibilité accordée).
    func reloadHotkeys() {
        // Réinstaller pendant l'écoute ferait perdre le relâchement de la touche.
        if state == .recording, settings.hotkeyMode == .hold { cancel(silently: true) }
        let choice = settings.hotkey
        let installed = hotkeys.install(choice)
        switch choice {
        case .fn where !accessibilityGranted:
            hotkeyWarning = "Le raccourci Fn ne fonctionne qu'avec l'autorisation Accessibilité (voir plus bas). Sinon, choisissez ⌥ Espace."
        case .optionSpace where !installed:
            hotkeyWarning = "⌥ Espace est déjà utilisé par une autre app. Choisissez Fn ou libérez ce raccourci."
        default:
            hotkeyWarning = nil
        }
        objectWillChange.send() // la consigne du menu dépend du raccourci et du mode
    }

    func refreshAccessibility() {
        let granted = Permissions.accessibilityGranted
        guard granted != accessibilityGranted else { return }
        accessibilityGranted = granted
        // Les moniteurs globaux installés avant l'autorisation ne reçoivent rien : on les recrée.
        reloadHotkeys()
    }

    // MARK: - Menu

    var statusLine: String {
        switch state {
        case .idle: return "Prêt : \(settings.usageHint)"
        case .recording: return "Écoute… (Échap pour annuler)"
        case .transcribing: return "Transcription…"
        case .error: return "Erreur : \(lastError ?? "inconnue")"
        }
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastTranscript, forType: .string)
    }

    // MARK: - Raccourci

    private func handleHotkey(_ edge: HotkeyEdge) {
        var edge = edge
        // Fn en mode « basculer » : on agit au relâchement, et seulement si Fn n'a pas servi à un raccourci
        // (Fn+flèche…). Sinon, un raccourci système arrêterait la dictée et la transcrirait.
        if settings.hotkey == .fn, settings.hotkeyMode == .toggle {
            guard edge == .released, !hotkeys.lastPressWasChord else { return }
            edge = .pressed
        }
        switch HotkeyLogic.action(for: edge, mode: settings.hotkeyMode, state: state) {
        case .start: begin()
        case .stop: stop()
        case .ignore: break
        }
    }

    // MARK: - Enregistrement

    func begin() {
        guard HotkeyLogic.canStart(from: state) else { return }

        switch Permissions.microphone {
        case .granted:
            break
        case .notDetermined:
            // La fenêtre système s'affiche ; la touche est sans doute déjà relâchée, on ne démarre pas.
            Task { [weak self] in
                let granted = await Permissions.requestMicrophone()
                if granted {
                    self?.overlay.show(.info("Micro autorisé : vous pouvez dicter."), autoHideAfter: 2.5)
                } else {
                    self?.fail(Self.microphoneDeniedMessage)
                }
            }
            return
        case .denied:
            fail(Self.microphoneDeniedMessage)
            return
        }

        do {
            try capture.start()
        } catch {
            fail("Impossible de démarrer le micro : \(error.localizedDescription)")
            return
        }
        setState(.recording, error: nil)
        hotkeys.setEscapeEnabled(true)

        // Son et pastille après 0,2 s (le micro tourne déjà) : un Fn+flèche, annulé aussitôt, ne fait ni son ni clignotement.
        startSoundPlayed = false
        startFeedbackTask?.cancel()
        startFeedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self, !Task.isCancelled, self.state == .recording else { return }
            if self.settings.soundsEnabled {
                NSSound(named: "Tink")?.play()
                self.startSoundPlayed = true
            }
            self.overlay.show(.listening)
        }

        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateLevel() }
        }
        maxDurationTask?.cancel()
        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.maxRecordingDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    /// Fin de l'enregistrement : transcription (ou abandon silencieux si trop court).
    func stop() {
        guard state == .recording else { return }
        endRecordingSession()
        // Son de fin dès qu'il y a eu un son de début, même si l'appui était trop court (SPEC §6).
        if startSoundPlayed, settings.soundsEnabled { NSSound(named: "Pop")?.play() }
        guard let result = capture.finish() else {
            fail("Aucun audio enregistré.")
            return
        }
        guard TranscriptionRules.shouldTranscribe(duration: result.duration) else {
            try? FileManager.default.removeItem(at: result.url)
            setState(.idle, error: nil)
            overlay.hide()
            return
        }
        setState(.transcribing, error: nil)
        overlay.show(.transcribing)
        let fileURL = result.url
        transcriptionTask = Task { [weak self] in
            guard let self else {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            await self.transcribe(fileURL: fileURL)
        }
    }

    /// Échap : annule sans transcrire. `silently` : Fn+autre touche, on masque sans message.
    func cancel(silently: Bool) {
        guard state == .recording else { return }
        endRecordingSession()
        // Comme dans stop() : tout « Tink » est suivi d'un « Pop » (SPEC §6).
        if startSoundPlayed, settings.soundsEnabled { NSSound(named: "Pop")?.play() }
        capture.cancel()
        setState(.idle, error: nil)
        if silently {
            overlay.hide()
        } else {
            overlay.show(.info("Dictée annulée."), autoHideAfter: 1.5)
        }
    }

    private func endRecordingSession() {
        startFeedbackTask?.cancel()
        startFeedbackTask = nil
        levelTimer?.invalidate()
        levelTimer = nil
        maxDurationTask?.cancel()
        maxDurationTask = nil
        hotkeys.setEscapeEnabled(false)
    }

    private func updateLevel() {
        guard state == .recording else { return }
        overlay.level.value = capture.level
    }

    // MARK: - Transcription

    private func transcribe(fileURL: URL) async {
        // Le fichier audio est supprimé dans tous les cas (SPEC §2.5).
        defer { try? FileManager.default.removeItem(at: fileURL) }

        guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
            fail(OpenAIClient.ClientError.missingAPIKey.errorDescription ?? "Clé API OpenAI manquante.")
            return
        }
        let client = OpenAIClient(apiKey: apiKey)

        do {
            let raw = try await client.transcribe(
                audioURL: fileURL,
                model: store.model,
                language: store.language,
                prompt: store.vocabulary
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            // Nettoyage en échec : `nil`, et finalText retombe sur le texte brut.
            var cleaned: String?
            if TranscriptionRules.shouldCleanUp(enabled: store.cleanupEnabled, raw: raw) {
                cleaned = try? await client.cleanUp(text: raw, model: store.cleanupModel, vocabulary: store.vocabulary)
            }
            try Task.checkCancellation()

            // Texte final vide : RuleError.noSpeech (« Aucune parole détectée. »), affichée par le `catch` générique.
            let text = try TranscriptionRules.finalText(raw: raw, cleaned: cleaned)
            lastTranscript = text
            await deliver(text)
        } catch is CancellationError {
            setState(.idle, error: nil)
            overlay.hide()
        } catch let error as URLError where error.code == .cancelled {
            setState(.idle, error: nil)
            overlay.hide()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func deliver(_ text: String) async {
        // Sur ordinateur, le caractère avant le curseur est inconnu : texte inséré tel quel (SPEC §5).
        let insertion = TextJoiner.textToInsert(text, before: nil)
        let outcome = await inserter.insert(insertion, restoreClipboard: settings.restoreClipboard)
        setState(.idle, error: nil)
        switch outcome {
        case .pasted:
            overlay.hide()
        case .copiedOnly:
            overlay.show(.info("Texte copié : collez-le avec ⌘V"), autoHideAfter: 4)
        }
    }

    // MARK: - Fermeture

    /// Fermeture de l'app : le `defer` de `transcribe` ne s'exécutera pas, on supprime l'audio ici (SPEC §2.5).
    func shutdown() {
        if state == .recording {
            endRecordingSession()
            capture.cancel()
        }
        transcriptionTask?.cancel()
        Self.purgeLeftoverAudio()
    }

    /// Supprime les WAV laissés par une session interrompue (fermeture, plantage). SPEC §2.5 et §8.
    static func purgeLeftoverAudio() {
        let tmp = FileManager.default.temporaryDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.lastPathComponent.hasPrefix("dictee-") && url.pathExtension == "wav" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Utilitaires

    private static let microphoneDeniedMessage =
        "Accès au micro refusé. Autorisez Dictée dans Réglages Système > Confidentialité et sécurité > Micro."

    private func fail(_ message: String) {
        setState(.error, error: message)
        overlay.show(.error(message), autoHideAfter: 4)
    }

    private func setState(_ newState: DictationState, error: String?) {
        state = newState
        lastError = error
    }
}
