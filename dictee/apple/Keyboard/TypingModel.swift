import CoreGraphics
import Foundation
import UIKit

/// Frappe sur le clavier AZERTY (SPEC §9) : couches, majuscule, double espace, effacement répété,
/// accents par appui long, aperçu de touche. Les règles pures sont dans `Shared/KeyboardLogic/`.
///
/// Les touchers arrivent de `KeyTouchView` (UIKit, multi-touch) avec leur position dans la zone des touches ;
/// la touche visée est retrouvée par `KeyboardGeometry`, avec la même géométrie que l'affichage.
/// Pas de minuterie permanente : l'appui long et la répétition utilisent des `Task` annulées au relâchement.
@MainActor
final class TypingModel: ObservableObject {
    /// Bulle des accents ouverte par un appui long.
    struct AccentPopup: Equatable {
        let position: KeyPosition
        let keyFrame: CGRect
        let frame: CGRect
        /// Options dans l'ordre d'affichage (de gauche à droite).
        let options: [String]
        var selectedIndex: Int
    }

    @Published private(set) var layer: KeyboardLayer = .letters
    @Published private(set) var shift: ShiftState = .off
    /// Touches spéciales enfoncées (fond plus sombre).
    @Published private(set) var highlighted: Set<KeyPosition> = []
    /// Lettre dont l'aperçu agrandi est affiché.
    @Published private(set) var preview: KeyPosition?
    @Published private(set) var accentPopup: AccentPopup?
    @Published private(set) var showsGlobe = false
    @Published private(set) var returnKey: ReturnKeyKind = .standard

    var rows: [[KeyboardKey]] { KeyboardLayout.rows(for: layer, showsGlobe: showsGlobe) }

    private struct ActiveTouch {
        var position: KeyPosition
        var key: KeyboardKey
        var lastPoint: CGPoint
        let sequence: Int
        var longPressTask: Task<Void, Never>?
    }

    private static let longPressDelay: UInt64 = 400_000_000
    private static let deleteRepeatDelay: UInt64 = 450_000_000
    private static let deleteRepeatInterval: UInt64 = 90_000_000

    private weak var controller: KeyboardViewController?
    private var shiftLogic = ShiftLogic()
    private var touches: [ObjectIdentifier: ActiveTouch] = [:]
    private var touchSequence = 0
    private var accentTouch: ObjectIdentifier?
    private var deleteRepeatTask: Task<Void, Never>?
    /// Heure (horloge monotone) de la dernière espace tapée, pour le double espace.
    private var lastSpaceTime: TimeInterval?

    init(controller: KeyboardViewController) {
        self.controller = controller
    }

    // MARK: - Cycle de vie

    func appear() {
        updateTraits()
        refreshShift()
    }

    func disappear() {
        cancelAllTouches()
        lastSpaceTime = nil
        if layer != .letters { layer = .letters }
    }

    /// Le champ a changé (curseur déplacé, autre champ, texte inséré) : traits du champ et majuscule automatique.
    func documentChanged() {
        updateTraits()
        refreshShift()
    }

    /// Relit `needsInputModeSwitchKey` et `returnKeyType`.
    func updateTraits() {
        guard let controller else { return }
        let globe = controller.needsInputModeSwitchKey
        if globe != showsGlobe {
            cancelAllTouches()
            showsGlobe = globe
        }
        let kind = controller.returnKeyKind
        if kind != returnKey { returnKey = kind }
    }

    // MARK: - Touchers (appelés par KeyTouchView)

    func touchBegan(_ id: ObjectIdentifier, at point: CGPoint, in size: CGSize) {
        // Bulle d'accents ouverte : les autres doigts sont ignorés.
        guard accentTouch == nil else { return }
        let rows = self.rows
        guard let position = KeyboardGeometry.position(at: point, rows: rows, size: size) else { return }
        let key = rows[position.row][position.column]

        // Frappe rapide à deux doigts : la lettre précédente est tapée dès qu'un autre doigt se pose.
        commitPendingCharacters()
        controller?.playClick()

        switch key {
        case .shift:
            shiftLogic.tap(at: ProcessInfo.processInfo.systemUptime)
            syncShift()
            return
        case .delete:
            deleteOnce()
            startDeleteRepeat()
        default:
            break
        }

        touchSequence += 1
        var touch = ActiveTouch(position: position, key: key, lastPoint: point, sequence: touchSequence, longPressTask: nil)
        if key.isCharacter {
            touch.longPressTask = makeLongPressTask(for: id, size: size)
        }
        touches[id] = touch
        refreshVisuals()
    }

    func touchMoved(_ id: ObjectIdentifier, to point: CGPoint, in size: CGSize) {
        guard var touch = touches[id] else { return }
        touch.lastPoint = point

        if accentTouch == id, var popup = accentPopup {
            let index = KeyboardGeometry.accentIndex(atX: point.x, popupFrame: popup.frame, optionCount: popup.options.count)
            if index != popup.selectedIndex {
                popup.selectedIndex = index
                accentPopup = popup
            }
            touches[id] = touch
            return
        }

        // Glisser d'une lettre à l'autre avant de relâcher, comme sur iOS.
        if touch.key.isCharacter {
            let rows = self.rows
            if let position = KeyboardGeometry.position(at: point, rows: rows, size: size), position != touch.position {
                let key = rows[position.row][position.column]
                if key.isCharacter {
                    touch.longPressTask?.cancel()
                    touch.position = position
                    touch.key = key
                    touch.longPressTask = makeLongPressTask(for: id, size: size)
                }
            }
        }
        touches[id] = touch
        refreshVisuals()
    }

    func touchEnded(_ id: ObjectIdentifier, at point: CGPoint, in size: CGSize) {
        guard let touch = touches.removeValue(forKey: id) else { return }
        touch.longPressTask?.cancel()

        if accentTouch == id {
            accentTouch = nil
            let popup = accentPopup
            accentPopup = nil
            // Relâcher nettement sous la touche annule le choix.
            if let popup, point.y < popup.keyFrame.maxY + popup.keyFrame.height,
               popup.options.indices.contains(popup.selectedIndex) {
                typeText(popup.options[popup.selectedIndex])
            }
            refreshVisuals()
            return
        }

        let stillOnKey = KeyboardGeometry.position(at: point, rows: rows, size: size) == touch.position
        switch touch.key {
        case let .character(character):
            typeCharacter(character)
        case .delete:
            stopDeleteRepeat()
        case .space:
            if stillOnKey { typeSpace() }
        case .returnKey:
            if stillOnKey { typeText("\n") }
        case let .layer(target):
            if stillOnKey { setLayer(target) }
        case .globe:
            // Normalement géré par le bouton UIKit (handleInputModeList) posé sur la touche.
            if stillOnKey { controller?.advanceToNextInputMode() }
        case .shift:
            break
        }
        refreshVisuals()
    }

    func touchCancelled(_ id: ObjectIdentifier) {
        guard let touch = touches.removeValue(forKey: id) else { return }
        touch.longPressTask?.cancel()
        if touch.key == .delete { stopDeleteRepeat() }
        if accentTouch == id {
            accentTouch = nil
            accentPopup = nil
        }
        refreshVisuals()
    }

    func cancelAllTouches() {
        for touch in touches.values { touch.longPressTask?.cancel() }
        touches.removeAll()
        stopDeleteRepeat()
        accentTouch = nil
        if accentPopup != nil { accentPopup = nil }
        refreshVisuals()
    }

    /// Activation d'une touche par VoiceOver (double toucher sur l'élément d'accessibilité).
    func activate(_ position: KeyPosition) {
        let rows = self.rows
        guard rows.indices.contains(position.row), rows[position.row].indices.contains(position.column) else { return }
        controller?.playClick()
        switch rows[position.row][position.column] {
        case let .character(character): typeCharacter(character)
        case .shift:
            shiftLogic.tap(at: ProcessInfo.processInfo.systemUptime)
            syncShift()
        case .delete: deleteOnce()
        case .space: typeSpace()
        case .returnKey: typeText("\n")
        case let .layer(target): setLayer(target)
        case .globe: controller?.advanceToNextInputMode()
        }
    }

    func playClick() {
        controller?.playClick()
    }

    /// Branche le bouton UIKit transparent posé sur 🌐 (toucher = clavier suivant, appui long = liste des claviers).
    func attachInputModeSwitch(to control: UIControl) {
        controller?.attachInputModeSwitch(to: control)
    }

    /// Cellule de la touche 🌐 dans une zone de cette taille, ou `nil` si elle n'est pas affichée.
    func globeCellFrame(in size: CGSize) -> CGRect? {
        let rows = self.rows
        let cells = KeyboardGeometry.cellFrames(for: rows, in: size)
        for (rowIndex, row) in rows.enumerated() {
            if let column = row.firstIndex(of: .globe) {
                return cells[rowIndex][column]
            }
        }
        return nil
    }

    /// Libellé lu par VoiceOver pour une touche.
    func accessibilityLabel(for key: KeyboardKey) -> String {
        switch key {
        case let .character(character):
            return KeyboardLayout.output(for: character, layer: layer, shift: shift)
        case .shift:
            switch shift {
            case .off: return "Majuscule"
            case .once: return "Majuscule activée"
            case .locked: return "Verrouillage des majuscules"
            }
        case .delete: return "Effacer"
        case let .layer(target):
            switch target {
            case .letters: return "Lettres"
            case .numbers: return "Chiffres"
            case .symbols: return "Symboles"
            }
        case .globe: return "Clavier suivant"
        case .space: return "Espace"
        case .returnKey: return returnKey.label
        }
    }

    // MARK: - Frappe

    private func typeCharacter(_ character: String) {
        typeText(KeyboardLayout.output(for: character, layer: layer, shift: shift))
    }

    private func typeText(_ text: String) {
        controller?.insert(text)
        lastSpaceTime = nil
        refreshShift()
    }

    /// Espace, ou « . » si c'est un double espace (SPEC §9).
    private func typeSpace() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = lastSpaceTime.map { now - $0 }
        if DoubleSpaceRule.shouldInsertPeriod(contextBefore: controller?.contextBeforeInput, secondsSinceLastSpace: elapsed) {
            controller?.deleteBackward()
            controller?.insert(DoubleSpaceRule.replacement)
            lastSpaceTime = nil
        } else {
            controller?.insert(" ")
            lastSpaceTime = now
        }
        refreshShift()
    }

    private func deleteOnce() {
        controller?.deleteBackward()
        lastSpaceTime = nil
        refreshShift()
    }

    private func setLayer(_ target: KeyboardLayer) {
        cancelAllTouches()
        if layer != target { layer = target }
        if target == .letters { refreshShift() }
        controller?.refreshPredictions()
    }

    /// Tape tout de suite les lettres encore enfoncées (frappe à deux doigts).
    private func commitPendingCharacters() {
        let pending = touches
            .filter { $0.value.key.isCharacter }
            .sorted { $0.value.sequence < $1.value.sequence }
        for (id, touch) in pending {
            touch.longPressTask?.cancel()
            touches[id] = nil
            if case let .character(character) = touch.key {
                typeCharacter(character)
            }
        }
    }

    // MARK: - Majuscule

    /// Majuscule simple consommée et majuscule automatique réévaluée selon le texte avant le curseur.
    private func refreshShift() {
        guard let controller else { return }
        let should = AutoCapitalization.shouldCapitalize(
            mode: controller.autoCapitalizationMode,
            contextBefore: controller.contextBeforeInput
        )
        shiftLogic.applyAutoCapitalization(should)
        syncShift()
    }

    private func syncShift() {
        if shift != shiftLogic.state { shift = shiftLogic.state }
    }

    // MARK: - Appui long et répétition

    private func makeLongPressTask(for id: ObjectIdentifier, size: CGSize) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: TypingModel.longPressDelay)
            } catch {
                return
            }
            self?.showAccents(for: id, size: size)
        }
    }

    private func showAccents(for id: ObjectIdentifier, size: CGSize) {
        guard accentTouch == nil, let touch = touches[id], case let .character(character) = touch.key else { return }
        let options = AccentTable.variants(for: KeyboardLayout.output(for: character, layer: layer, shift: shift))
        guard !options.isEmpty else { return }
        let cells = KeyboardGeometry.cellFrames(for: rows, in: size)
        guard cells.indices.contains(touch.position.row),
              cells[touch.position.row].indices.contains(touch.position.column) else { return }
        let keyFrame = KeyboardGeometry.keyFrame(forCell: cells[touch.position.row][touch.position.column])
        let layout = KeyboardGeometry.accentPopup(keyFrame: keyFrame, optionCount: options.count, containerWidth: size.width)
        let displayed = layout.reversed ? Array(options.reversed()) : options
        let selected = KeyboardGeometry.accentIndex(atX: touch.lastPoint.x, popupFrame: layout.frame, optionCount: displayed.count)
        accentTouch = id
        accentPopup = AccentPopup(
            position: touch.position,
            keyFrame: keyFrame,
            frame: layout.frame,
            options: displayed,
            selectedIndex: selected
        )
        refreshVisuals()
    }

    private func startDeleteRepeat() {
        deleteRepeatTask?.cancel()
        deleteRepeatTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: TypingModel.deleteRepeatDelay)
            } catch {
                return
            }
            while !Task.isCancelled {
                guard let self else { return }
                self.controller?.playClick()
                self.deleteOnce()
                do {
                    try await Task.sleep(nanoseconds: TypingModel.deleteRepeatInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func stopDeleteRepeat() {
        deleteRepeatTask?.cancel()
        deleteRepeatTask = nil
    }

    // MARK: - Affichage

    private func refreshVisuals() {
        let special = Set(touches.values.filter({ !$0.key.isCharacter }).map(\.position))
        let latestCharacter = accentTouch == nil
            ? touches.values.filter({ $0.key.isCharacter }).max(by: { $0.sequence < $1.sequence })?.position
            : nil
        if highlighted != special { highlighted = special }
        if preview != latestCharacter { preview = latestCharacter }
    }
}
