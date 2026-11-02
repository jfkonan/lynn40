import AppKit

/// Copie complète du presse-papiers (tous les éléments, tous les types) pour le restaurer après le collage.
struct PasteboardSnapshot: Equatable {
    struct Entry: Equatable {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    /// Un tableau d'entrées par NSPasteboardItem, dans l'ordre d'origine.
    let items: [[Entry]]

    var isEmpty: Bool { items.isEmpty }

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item -> [Entry] in
            item.types.compactMap { type -> Entry? in
                guard let data = item.data(forType: type) else { return nil }
                return Entry(type: type, data: data)
            }
        }
        return PasteboardSnapshot(items: items.filter { !$0.isEmpty })
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let objects = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for entry in entries {
                item.setData(entry.data, forType: entry.type)
            }
            return item
        }
        if !objects.isEmpty {
            pasteboard.writeObjects(objects)
        }
    }
}
