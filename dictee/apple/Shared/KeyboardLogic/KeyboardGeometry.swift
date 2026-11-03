import CoreGraphics
import Foundation

/// Géométrie des touches, calculée à partir de la taille réelle de la zone (GeometryReader) : la même disposition
/// tient sur un iPhone SE comme sur un Pro Max. Les cellules sont jointives (pas de zone morte entre les touches) ;
/// chaque touche dessine son fond en retrait de `keyInsets` dans sa cellule.
enum KeyboardGeometry {
    /// Marge extérieure gauche/droite et haut/bas de la zone des touches.
    static let outerHorizontalPadding: CGFloat = 3
    static let outerVerticalPadding: CGFloat = 3
    /// Retrait du fond de la touche dans sa cellule (moitié de l'espacement entre touches).
    static let keyHorizontalInset: CGFloat = 3
    static let keyVerticalInset: CGFloat = 5.5

    /// Cellules (zones de toucher) de chaque touche, dans le repère de la zone des touches.
    static func cellFrames(for rows: [[KeyboardKey]], in size: CGSize) -> [[CGRect]] {
        guard !rows.isEmpty, size.width > 0, size.height > 0 else { return rows.map { $0.map { _ in CGRect.zero } } }
        let usableWidth = max(size.width - 2 * outerHorizontalPadding, 0)
        let rowHeight = max(size.height - 2 * outerVerticalPadding, 0) / CGFloat(rows.count)
        return rows.indices.map { (rowIndex: Int) -> [CGRect] in
            let units = KeyboardLayout.widthUnits(for: rows[rowIndex])
            let total = units.reduce(0, +)
            let scale = total > 0 ? usableWidth / CGFloat(total) : 0
            var x = outerHorizontalPadding
            let y = outerVerticalPadding + CGFloat(rowIndex) * rowHeight
            return units.map { (unit: Double) -> CGRect in
                let width = CGFloat(unit) * scale
                defer { x += width }
                return CGRect(x: x, y: y, width: width, height: rowHeight)
            }
        }
    }

    /// Fond visible de la touche dans sa cellule.
    static func keyFrame(forCell cell: CGRect) -> CGRect {
        cell.insetBy(dx: keyHorizontalInset, dy: keyVerticalInset)
    }

    /// Touche sous le doigt. Un point dans une marge est rattaché à la touche la plus proche :
    /// aucun toucher dans la zone n'est perdu.
    static func position(at point: CGPoint, rows: [[KeyboardKey]], size: CGSize) -> KeyPosition? {
        let frames = cellFrames(for: rows, in: size)
        guard let firstRow = frames.first, let first = firstRow.first, first.height > 0 else { return nil }
        let rowHeight = first.height
        let rawRow = Int(((point.y - outerVerticalPadding) / rowHeight).rounded(.down))
        let row = min(max(rawRow, 0), frames.count - 1)
        let cells = frames[row]
        guard !cells.isEmpty else { return nil }
        let column = cells.firstIndex(where: { point.x < $0.maxX }) ?? cells.count - 1
        return KeyPosition(row: row, column: column)
    }

    // MARK: - Bulle des accents

    /// Largeur d'une case de la bulle : un peu plus large que la touche, pour viser facilement.
    static func accentCellWidth(forKey keyFrame: CGRect) -> CGFloat {
        max(keyFrame.width + 6, 30)
    }

    /// Bulle des accents au-dessus de la touche. Les options partent vers la droite, la première au-dessus de la touche ;
    /// près du bord droit, elles partent vers la gauche et l'ordre d'affichage est inversé (`reversed` vrai) pour que
    /// la première option reste au-dessus de la touche.
    static func accentPopup(keyFrame: CGRect, optionCount: Int, containerWidth: CGFloat) -> (frame: CGRect, reversed: Bool) {
        let count = CGFloat(max(optionCount, 1))
        let cell = accentCellWidth(forKey: keyFrame)
        let width = cell * count
        let height = keyFrame.height + 4
        let margin: CGFloat = 2
        var x = keyFrame.midX - cell / 2
        var reversed = false
        if x + width > containerWidth - margin {
            x = keyFrame.midX + cell / 2 - width
            reversed = true
        }
        x = min(max(x, margin), max(containerWidth - margin - width, margin))
        let y = keyFrame.minY - height - 6
        return (CGRect(x: x, y: y, width: width, height: height), reversed)
    }

    /// Case de la bulle visée par le doigt (abscisse), bornée aux options existantes.
    static func accentIndex(atX x: CGFloat, popupFrame: CGRect, optionCount: Int) -> Int {
        guard optionCount > 0, popupFrame.width > 0 else { return 0 }
        let cell = popupFrame.width / CGFloat(optionCount)
        let raw = Int(((x - popupFrame.minX) / cell).rounded(.down))
        return min(max(raw, 0), optionCount - 1)
    }

    // MARK: - Aperçu agrandi

    /// Aperçu agrandi d'une lettre : plus large que la touche et posé au-dessus d'elle, borné à la zone.
    static func previewFrame(keyFrame: CGRect, containerWidth: CGFloat) -> CGRect {
        let width = keyFrame.width + 16
        let height = keyFrame.height * 2.1
        var x = keyFrame.midX - width / 2
        x = min(max(x, 0), max(containerWidth - width, 0))
        return CGRect(x: x, y: keyFrame.maxY - height, width: width, height: height)
    }
}
