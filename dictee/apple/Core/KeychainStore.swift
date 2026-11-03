import Foundation
import Security

/// Stockage des clés API dans le Trousseau (iOS et macOS), jamais dans le code ni dans l'App Group.
/// Une clé par fournisseur (SPEC §4) : service `com.dictee.openai`, compte `apiKey` pour OpenAI (inchangé,
/// pour garder les clés déjà enregistrées), `apiKey.mistral` pour Mistral, `apiKey.microsoft` pour Microsoft.
enum KeychainStore {
    private static let service = "com.dictee.openai"

    enum KeychainError: LocalizedError {
        case status(OSStatus)
        var errorDescription: String? {
            if case let .status(code) = self { return "Erreur Trousseau (\(code))." }
            return nil
        }
    }

    /// Enregistre la clé du fournisseur (OpenAI par défaut). Une clé vide efface la clé existante.
    static func saveAPIKey(_ key: String, for provider: TranscriptionProvider = .openai) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        deleteAPIKey(for: provider)
        guard !trimmed.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
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

    /// Clé du fournisseur (OpenAI par défaut), ou `nil` si elle n'est pas enregistrée.
    static func loadAPIKey(for provider: TranscriptionProvider = .openai) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Les trois clés, pour `TranscriptionService.transcribe` (et le nettoyage, qui utilise la clé OpenAI).
    static func loadAllKeys() -> ProviderKeys {
        ProviderKeys(
            openAI: loadAPIKey(for: .openai),
            mistral: loadAPIKey(for: .mistral),
            microsoft: loadAPIKey(for: .microsoft)
        )
    }

    /// Aperçu affichable de la clé : 3 premiers et 4 derniers caractères, ex. `sk-…abcd` (SPEC §4).
    static func preview(of key: String?) -> String? {
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        guard key.count > 8 else { return "••••" }
        return "\(key.prefix(3))…\(key.suffix(4))"
    }

    static func deleteAPIKey(for provider: TranscriptionProvider = .openai) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
