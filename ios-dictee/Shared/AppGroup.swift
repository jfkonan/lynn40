import Foundation

/// Accès à l'espace partagé (App Group) entre l'app et le clavier.
/// L'identifiant est injecté dans les deux Info.plist à partir de APP_GROUP_ID (Config/Signing.xcconfig).
enum AppGroup {
    static var identifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String) ?? ""
    }

    static var defaults: UserDefaults? {
        let id = identifier
        guard !id.isEmpty else { return nil }
        return UserDefaults(suiteName: id)
    }
}

/// Signaux échangés entre le clavier et l'app via les notifications Darwin (inter-processus).
/// Ces notifications ne transportent pas de données : le contenu passe par SharedStore.
enum DictationSignal: String, CaseIterable {
    /// Clavier -> app
    case startRecording = "com.dictee.signal.startRecording"
    case stopRecording = "com.dictee.signal.stopRecording"
    case cancelRecording = "com.dictee.signal.cancelRecording"
    /// App -> clavier
    case stateChanged = "com.dictee.signal.stateChanged"
    case transcriptReady = "com.dictee.signal.transcriptReady"
}
