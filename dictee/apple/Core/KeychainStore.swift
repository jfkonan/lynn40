import Foundation
import Security

/// Stockage de la clé API OpenAI dans le Trousseau (iOS et macOS), jamais dans le code ni dans l'App Group.
enum KeychainStore {
    private static let service = "com.dictee.openai"
    private static let account = "apiKey"

    enum KeychainError: LocalizedError {
        case status(OSStatus)
        var errorDescription: String? {
            if case let .status(code) = self { return "Erreur Trousseau (\(code))." }
            return nil
        }
    }

    static func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        deleteAPIKey()
        guard !trimmed.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(trimmed.utf8),
        ]
        #if os(iOS)
        // Lisible en arrière-plan (l'app transcrit pendant que vous êtes dans une autre app).
        let accessibility: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        #else
        // Sur macOS, on reste sur le trousseau de session classique, qui ne demande aucun droit de signature.
        let accessibility: [String: Any] = [:]
        #endif
        let status = SecItemAdd(query.merging(accessibility) { $1 } as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Aperçu affichable de la clé : 3 premiers et 4 derniers caractères, ex. `sk-…abcd` (SPEC §4).
    static func preview(of key: String?) -> String? {
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        guard key.count > 8 else { return "••••" }
        return "\(key.prefix(3))…\(key.suffix(4))"
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
