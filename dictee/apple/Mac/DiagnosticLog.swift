import Foundation

/// Journal de diagnostic du Mac : une ligne par dictée dans `~/Library/Logs/Dictee/dictee.log`
/// (date, fournisseur, durée relâchement → texte, repères du continu, étapes). **Jamais** le texte dicté ni une clé.
/// Sert à mesurer sans demander à l'utilisateur de recopier le menu. Taille bornée : le fichier est tronqué au-delà de 200 Ko.
enum DiagnosticLog {
    static let maxSize = 200_000

    static var url: URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Dictee", isDirectory: true)
        return logs.appendingPathComponent("dictee.log")
    }

    static func append(_ line: String) {
        let url = Self.url
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(stamp) \(line)\n"
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int, size > maxSize {
            try? FileManager.default.removeItem(at: url)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            handle.closeFile()
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }
}
