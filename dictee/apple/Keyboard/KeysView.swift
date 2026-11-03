import SwiftUI
import UIKit

/// Zone des touches. La géométrie vient de `KeyboardGeometry` (largeur calculée avec GeometryReader) ;
/// le dessin est en SwiftUI, les touchers passent par `KeyTouchSurface` (UIKit, multi-touch) posée au-dessus.
struct KeysView: View {
    @ObservedObject var typing: TypingModel
    /// Faux pendant que le menu des styles est ouvert : les touchers vont alors au menu.
    let interactive: Bool

    var body: some View {
        GeometryReader { proxy in
            content(size: proxy.size)
        }
        .onDisappear { typing.cancelAllTouches() }
    }

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        let rows = typing.rows
        let cells = KeyboardGeometry.cellFrames(for: rows, in: size)
        ZStack(alignment: .topLeading) {
            KeyGrid(
                rows: rows,
                cells: cells,
                layer: typing.layer,
                shift: typing.shift,
                returnKey: typing.returnKey,
                highlighted: typing.highlighted
            )

            if let position = typing.preview, let character = characterValue(at: position, in: rows) {
                let keyFrame = KeyboardGeometry.keyFrame(forCell: cells[position.row][position.column])
                KeyPreview(
                    text: KeyboardLayout.output(for: character, layer: typing.layer, shift: typing.shift),
                    bubbleFrame: KeyboardGeometry.previewFrame(keyFrame: keyFrame, containerWidth: size.width),
                    keyHeight: keyFrame.height
                )
            }

            if let popup = typing.accentPopup {
                AccentBubble(popup: popup)
            }

            KeyTouchSurface(
                typing: typing,
                layer: typing.layer,
                shift: typing.shift,
                showsGlobe: typing.showsGlobe,
                interactive: interactive
            )
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func characterValue(at position: KeyPosition, in rows: [[KeyboardKey]]) -> String? {
        guard rows.indices.contains(position.row), rows[position.row].indices.contains(position.column),
              case let .character(character) = rows[position.row][position.column] else { return nil }
        return character
    }
}

// MARK: - Grille des touches

private struct KeyGrid: View {
    let rows: [[KeyboardKey]]
    let cells: [[CGRect]]
    let layer: KeyboardLayer
    let shift: ShiftState
    let returnKey: ReturnKeyKind
    let highlighted: Set<KeyPosition>

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                ForEach(0..<rows[rowIndex].count, id: \.self) { column in
                    keyCap(row: rowIndex, column: column)
                }
            }
        }
    }

    private func keyCap(row: Int, column: Int) -> some View {
        let keyRect = KeyboardGeometry.keyFrame(forCell: cells[row][column])
        return KeyCap(
            key: rows[row][column],
            layer: layer,
            shift: shift,
            returnKey: returnKey,
            pressed: highlighted.contains(KeyPosition(row: row, column: column))
        )
        .frame(width: max(keyRect.width, 0), height: max(keyRect.height, 0))
        .position(x: keyRect.midX, y: keyRect.midY)
    }
}

// MARK: - Touche

private struct KeyCap: View {
    let key: KeyboardKey
    let layer: KeyboardLayer
    let shift: ShiftState
    let returnKey: ReturnKeyKind
    let pressed: Bool

    var body: some View {
        ZStack {
            // Liseré inférieur dessiné par une forme décalée : moins coûteux qu'une ombre.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(KeyboardTheme.keyShadow)
                .offset(y: 1)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
            label
                .foregroundColor(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
        }
        .accessibilityHidden(true)
    }

    private var isProminentReturn: Bool {
        key == .returnKey && returnKey.isProminent
    }

    private var background: Color {
        if pressed { return KeyboardTheme.keyPressed }
        if isProminentReturn { return KeyboardTheme.accent }
        return key.isCharacter || key == .space ? KeyboardTheme.key : KeyboardTheme.specialKey
    }

    private var foreground: Color {
        isProminentReturn && !pressed ? .white : KeyboardTheme.keyText
    }

    @ViewBuilder
    private var label: some View {
        switch key {
        case let .character(character):
            Text(KeyboardLayout.output(for: character, layer: layer, shift: shift))
                .font(.system(size: layer == .letters ? 25 : 22))
        case .shift:
            Image(systemName: shiftSymbol)
                .font(.system(size: 18, weight: .medium))
        case .delete:
            Image(systemName: pressed ? "delete.left.fill" : "delete.left")
                .font(.system(size: 18, weight: .medium))
        case let .layer(target):
            Text(target.switchLabel)
                .font(.system(size: 16))
        case .globe:
            Image(systemName: "globe")
                .font(.system(size: 18))
        case .space:
            Text(KeyboardLayout.spaceLabel)
                .font(.system(size: 16))
        case .returnKey:
            Text(returnKey.label)
                .font(.system(size: 16))
        }
    }

    private var shiftSymbol: String {
        switch shift {
        case .off: return "shift"
        case .once: return "shift.fill"
        case .locked: return "capslock.fill"
        }
    }
}

// MARK: - Aperçu agrandi

private struct KeyPreview: View {
    let text: String
    let bubbleFrame: CGRect
    let keyHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 34))
                .foregroundColor(KeyboardTheme.keyText)
                .frame(maxWidth: .infinity)
                .frame(height: max(bubbleFrame.height - keyHeight, 0))
            Spacer(minLength: 0)
        }
        .frame(width: bubbleFrame.width, height: bubbleFrame.height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(KeyboardTheme.key)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        )
        .position(x: bubbleFrame.midX, y: bubbleFrame.midY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Bulle des accents

private struct AccentBubble: View {
    let popup: TypingModel.AccentPopup

    var body: some View {
        let cellWidth = popup.frame.width / CGFloat(max(popup.options.count, 1))
        HStack(spacing: 0) {
            ForEach(0..<popup.options.count, id: \.self) { index in
                let selected = index == popup.selectedIndex
                Text(popup.options[index])
                    .font(.system(size: 24))
                    .foregroundColor(selected ? .white : KeyboardTheme.keyText)
                    .frame(width: cellWidth, height: popup.frame.height)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected ? KeyboardTheme.accent : Color.clear)
                            .padding(3)
                    )
            }
        }
        .frame(width: popup.frame.width, height: popup.frame.height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(KeyboardTheme.key)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 1)
        )
        .position(x: popup.frame.midX, y: popup.frame.midY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Surface tactile (UIKit)

/// Reçoit tous les touchers de la zone (multi-touch, sans zone morte) et les transmet à `TypingModel`.
/// Un `UIButton` transparent est posé sur 🌐 pour `handleInputModeList(from:with:)`.
private struct KeyTouchSurface: UIViewRepresentable {
    let typing: TypingModel
    /// Couche, majuscule et 🌐 : passés pour que SwiftUI rappelle `updateUIView` quand ils changent
    /// (position du bouton 🌐, libellés VoiceOver).
    let layer: KeyboardLayer
    let shift: ShiftState
    let showsGlobe: Bool
    let interactive: Bool

    func makeUIView(context: Context) -> KeyTouchView {
        let view = KeyTouchView(frame: .zero)
        view.typing = typing
        typing.attachInputModeSwitch(to: view.globeButton)
        return view
    }

    func updateUIView(_ uiView: KeyTouchView, context: Context) {
        uiView.typing = typing
        uiView.isUserInteractionEnabled = interactive
        uiView.contentChanged()
    }
}

final class KeyTouchView: UIView {
    weak var typing: TypingModel?
    let globeButton = UIButton(type: .custom)
    private var cachedAccessibilityElements: [Any]?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        globeButton.backgroundColor = .clear
        globeButton.isHidden = true
        globeButton.accessibilityLabel = "Clavier suivant"
        globeButton.addTarget(self, action: #selector(globeTouchDown), for: .touchDown)
        addSubview(globeButton)
    }

    /// Couche ou 🌐 modifiés : position du bouton 🌐 et éléments d'accessibilité à recalculer.
    func contentChanged() {
        cachedAccessibilityElements = nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let globeFrame = typing?.globeCellFrame(in: bounds.size) {
            globeButton.frame = globeFrame
            globeButton.isHidden = false
        } else {
            globeButton.isHidden = true
        }
        cachedAccessibilityElements = nil
    }

    @objc private func globeTouchDown() {
        typing?.playClick()
    }

    // MARK: Touchers

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let typing else { return }
        for touch in touches {
            typing.touchBegan(ObjectIdentifier(touch), at: touch.location(in: self), in: bounds.size)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let typing else { return }
        for touch in touches {
            typing.touchMoved(ObjectIdentifier(touch), to: touch.location(in: self), in: bounds.size)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let typing else { return }
        for touch in touches {
            typing.touchEnded(ObjectIdentifier(touch), at: touch.location(in: self), in: bounds.size)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let typing else { return }
        for touch in touches {
            typing.touchCancelled(ObjectIdentifier(touch))
        }
    }

    // MARK: Accessibilité (VoiceOver)

    override var accessibilityElements: [Any]? {
        get {
            if let cachedAccessibilityElements { return cachedAccessibilityElements }
            let elements = makeAccessibilityElements()
            cachedAccessibilityElements = elements
            return elements
        }
        set {
            cachedAccessibilityElements = newValue
        }
    }

    private func makeAccessibilityElements() -> [Any] {
        guard let typing else { return [] }
        let rows = typing.rows
        let cells = KeyboardGeometry.cellFrames(for: rows, in: bounds.size)
        var elements: [Any] = []
        for (rowIndex, row) in rows.enumerated() {
            for (column, key) in row.enumerated() {
                if key == .globe {
                    if !globeButton.isHidden { elements.append(globeButton) }
                    continue
                }
                let element = KeyAccessibilityElement(accessibilityContainer: self)
                element.accessibilityLabel = typing.accessibilityLabel(for: key)
                element.accessibilityTraits = .keyboardKey
                element.accessibilityFrameInContainerSpace = cells[rowIndex][column]
                let position = KeyPosition(row: rowIndex, column: column)
                element.onActivate = { [weak typing] in
                    typing?.activate(position)
                }
                elements.append(element)
            }
        }
        return elements
    }
}

/// Touche exposée à VoiceOver ; l'activation (double toucher) appelle `onActivate`.
private final class KeyAccessibilityElement: UIAccessibilityElement {
    var onActivate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        guard let onActivate else { return false }
        onActivate()
        return true
    }
}
