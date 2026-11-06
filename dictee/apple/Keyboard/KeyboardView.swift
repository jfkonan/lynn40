import SwiftUI

/// Racine du clavier : barre supérieure (☰, pastille de style, micro), puis les touches ou le panneau rapide.
struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardModel
    /// Observé seulement par `KeysView` : une frappe ne redessine pas la barre supérieure.
    let typing: TypingModel
    /// Observé seulement par `PredictionBar`.
    let prediction: PredictionModel

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var compact: Bool { verticalSizeClass == .compact }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model, compact: compact)
                .frame(height: compact ? 40 : 52)

            // Toujours présente (hauteur stable, comme sur iOS) ; vide quand il n'y a rien à proposer.
            PredictionBar(prediction: prediction, compact: compact)
                .frame(height: compact ? 32 : 38)

            ZStack(alignment: .topTrailing) {
                if model.panelOpen {
                    QuickPanel(model: model)
                } else {
                    KeysView(typing: typing, interactive: !model.styleMenuOpen)
                }

                if model.styleMenuOpen {
                    // Toucher à côté du menu : il se ferme.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { model.closeStyleMenu() }
                        .accessibilityHidden(true)
                    StyleMenu(model: model)
                        .padding(.trailing, compact ? 46 : 58)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(KeyboardTheme.background)
        // Mode clair/sombre décidé par le contrôleur (champ puis système) : voir `KeyboardAppearanceLogic`.
        .environment(\.colorScheme, model.colorScheme)
    }
}

// MARK: - Barre de suggestions

/// Trois propositions séparées par de fins traits, comme la barre prédictive d'iOS (SPEC §9).
private struct PredictionBar: View {
    @ObservedObject var prediction: PredictionModel
    let compact: Bool

    var body: some View {
        HStack(spacing: 0) {
            if let correction = prediction.lastCorrection {
                Button {
                    prediction.revertCorrection()
                } label: {
                    Text("\u{201C}\(correction.original)\u{201D}")
                        .font(.system(size: compact ? 15 : 17))
                        .foregroundColor(KeyboardTheme.keyText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rétablir \(correction.original)")
                .accessibilityHint("Annule la correction automatique.")
                if !prediction.suggestions.isEmpty {
                    Rectangle()
                        .fill(KeyboardTheme.secondaryText.opacity(0.35))
                        .frame(width: 1)
                        .padding(.vertical, 6)
                }
            }
            ForEach(Array(prediction.suggestions.enumerated()), id: \.offset) { index, suggestion in
                if index > 0 {
                    Rectangle()
                        .fill(KeyboardTheme.secondaryText.opacity(0.35))
                        .frame(width: 1)
                        .padding(.vertical, 6)
                }
                Button {
                    prediction.accept(suggestion)
                } label: {
                    Text(suggestion)
                        .font(.system(size: compact ? 15 : 17))
                        .foregroundColor(KeyboardTheme.keyText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suggestion : \(suggestion)")
                .accessibilityHint("Remplace le mot en cours.")
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Barre supérieure

private struct TopBar: View {
    @ObservedObject var model: KeyboardModel
    let compact: Bool

    private var micDiameter: CGFloat { compact ? 34 : 44 }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.togglePanel()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: compact ? 19 : 22, weight: .regular))
                    .foregroundColor(KeyboardTheme.keyText)
                    .frame(width: 44, height: micDiameter)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.panelOpen ? "Fermer le panneau rapide" : "Panneau rapide")

            if let message = model.message {
                Button {
                    model.dismissMessage()
                } label: {
                    Text(message.text)
                        .font(.footnote)
                        .foregroundColor(message.isError ? KeyboardTheme.error : KeyboardTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(compact ? 2 : 3)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Touchez pour masquer ce message.")
            } else {
                Spacer(minLength: 0)
                styleChip
            }

            micButton
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
    }

    private var styleChip: some View {
        Button {
            model.toggleStyleMenu()
        } label: {
            Text(model.chipText)
                .font(.system(size: compact ? 15 : 17, weight: .medium))
                .foregroundColor(KeyboardTheme.keyText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, compact ? 16 : 22)
                .frame(minWidth: compact ? 84 : 104)
                .frame(height: micDiameter)
                .background(Capsule().fill(KeyboardTheme.chip))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Style d'écriture : \(model.style.label)")
        .accessibilityHint("Touchez pour choisir le style.")
    }

    private var micButton: some View {
        ZStack {
            Circle()
                .fill(micColor)
            if model.phase == .transcribing {
                ProgressView()
                    .tint(KeyboardTheme.micIcon)
            } else {
                Image(systemName: micSymbol)
                    .font(.system(size: compact ? 15 : 19, weight: .semibold))
                    .foregroundColor(model.phase == .recording ? .white : KeyboardTheme.micIcon)
            }
        }
        .frame(width: micDiameter, height: micDiameter)
        .opacity(model.phase == .needsSession || model.phase == .noFullAccess ? 0.75 : 1)
        .contentShape(Circle())
        // Appui long pendant l'écoute : annulation. Toucher : démarrer, arrêter ou ouvrir l'app.
        .gesture(
            LongPressGesture(minimumDuration: 0.6)
                .exclusively(before: TapGesture())
                .onEnded { value in
                    switch value {
                    case .first: model.micLongPressed()
                    case .second: model.micTapped()
                    }
                }
        )
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(micAccessibilityLabel)
        .accessibilityAction { model.micTapped() }
        .accessibilityAction(named: Text("Annuler la dictée")) { model.cancelIfRecording() }
    }

    private var micColor: Color {
        model.phase == .recording ? KeyboardTheme.micRecording : KeyboardTheme.micBackground
    }

    private var micSymbol: String {
        switch model.phase {
        case .recording: return "stop.fill"
        case .needsSession: return "arrow.up.forward.app"
        case .noFullAccess: return "lock.fill"
        default: return "mic.fill"
        }
    }

    private var micAccessibilityLabel: String {
        switch model.phase {
        case .recording: return "Terminer la dictée"
        case .transcribing: return "Transcription en cours"
        case .needsSession: return "Démarrer une session dans l'app Dictée"
        case .noFullAccess: return "Accès complet requis"
        default: return "Dicter"
        }
    }
}

// MARK: - Menu des styles

private struct StyleMenu: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(WritingStyle.allCases) { style in
                Button {
                    model.selectStyle(style)
                } label: {
                    HStack {
                        Text(style.label)
                        Spacer(minLength: 8)
                        if style == model.style {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .font(.system(size: 16))
                    .foregroundColor(KeyboardTheme.keyText)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(style == model.style ? .isSelected : [])
                if style != WritingStyle.allCases.last {
                    Divider()
                }
            }
        }
        .frame(width: 190)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(KeyboardTheme.chip)
                .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - Panneau rapide

private struct QuickPanel: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                historySection

                choiceSection("Style d'écriture") {
                    ForEach(WritingStyle.allCases) { style in
                        ChoiceChip(title: style.label, selected: style == model.style) {
                            model.selectStyle(style)
                        }
                    }
                }

                choiceSection("Fournisseur") {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        ChoiceChip(title: provider.displayName, selected: provider == model.provider) {
                            model.selectProvider(provider)
                        }
                    }
                }

                choiceSection("Langue") {
                    ForEach(model.languageChoices) { choice in
                        ChoiceChip(title: choice.label, selected: choice.code == model.language) {
                            model.selectLanguage(choice.code)
                        }
                    }
                }

                HStack(spacing: 10) {
                    PanelButton(title: "Ouvrir Dictée", systemImage: "arrow.up.forward.app") {
                        model.openDicteeSettings()
                    }
                    PanelButton(title: "Fermer", systemImage: "keyboard") {
                        model.closePanel()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Dernières transcriptions")
            if model.history.isEmpty {
                Text("Aucune transcription pour l'instant.")
                    .font(.footnote)
                    .foregroundColor(KeyboardTheme.secondaryText)
            } else {
                ForEach(model.history) { item in
                    Button {
                        model.insertFromHistory(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text)
                                .font(.subheadline)
                                .foregroundColor(KeyboardTheme.keyText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(item.createdAt, style: .time)
                                .font(.caption2)
                                .foregroundColor(KeyboardTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KeyboardTheme.chip))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Touchez pour insérer ce texte.")
                }
                Button {
                    model.clearHistory()
                } label: {
                    Label("Effacer l'historique", systemImage: "trash")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(KeyboardTheme.error)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func choiceSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    content()
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(KeyboardTheme.secondaryText)
            .textCase(.uppercase)
    }
}

/// Pastille de choix du panneau (style, fournisseur, langue).
private struct ChoiceChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : KeyboardTheme.keyText)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(selected ? KeyboardTheme.accent : KeyboardTheme.chip))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Bouton large du bas du panneau (« Ouvrir Dictée », « Fermer »).
private struct PanelButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(KeyboardTheme.keyText)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KeyboardTheme.chip))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
