import AppKit
import ApplicationServices
import AVFoundation

/// Autorisations système dont Dictée a besoin : Micro (enregistrer) et Accessibilité (Fn et ⌘V simulé).
enum Permissions {
    enum Status: Equatable {
        case granted
        case denied
        case notDetermined
    }

    enum Pane {
        case microphone
        case accessibility
        case keyboard

        var url: URL {
            switch self {
            case .microphone:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            case .accessibility:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            case .keyboard:
                return URL(string: "x-apple.systempreferences:com.apple.preference.keyboard")!
            }
        }
    }

    static var microphone: Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied // .denied, .restricted
        }
    }

    /// Hors MainActor (fonction statique d'un enum non isolé) : macOS rappelle sur un thread quelconque.
    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Affiche la demande système, qui ajoute Dictée à la liste Accessibilité.
    /// La clé est la valeur de kAXTrustedCheckOptionPrompt, écrite en clair pour éviter le pont Unmanaged.
    @discardableResult
    static func promptAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func openSystemSettings(_ pane: Pane) {
        NSWorkspace.shared.open(pane.url)
    }
}
