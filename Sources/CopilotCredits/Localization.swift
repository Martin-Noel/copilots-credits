import CopilotCreditsCore
import Foundation

/// Language chosen in the menu; "system" follows the macOS preferences.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, fr, en

    var id: String { rawValue }

    static let defaultsKey = "appLanguage"

    /// Read from UserDefaults on every call: usable outside the MainActor (errors, notifications).
    static var current: AppLanguage {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(AppLanguage.init) ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// Effective language: French if it is the system's preferred language, English otherwise.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("fr") ? .fr : .en
    }

    /// Name shown in the picker (each language in its own language).
    var displayName: String {
        switch self {
        case .system: return tr("Langue du système", "System language")
        case .fr: return "Français"
        case .en: return "English"
        }
    }
}

/// String translated into the chosen language. Only two languages: FR/EN pairs
/// stay readable in place, and switching applies without relaunching the app.
func tr(_ fr: String, _ en: String) -> String {
    AppLanguage.current.resolved == .fr ? fr : en
}

enum L10n {
    /// Formatting locale: chosen language + system region (e.g. en_FR, fr_CA).
    static var locale: Locale {
        let lang = AppLanguage.current
        guard lang != .system else { return .current }
        guard let region = Locale.current.region?.identifier else { return Locale(identifier: lang.rawValue) }
        return Locale(identifier: "\(lang.rawValue)_\(region)")
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    static func credits(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }

    /// Error messages from the Core module (its errorDescriptions are English only).
    static func message(for error: Error) -> String {
        switch error {
        case DeviceFlowError.expired:
            return tr("Le code a expiré. Relancez la connexion.",
                      "The code has expired. Please sign in again.")
        case DeviceFlowError.denied:
            return tr("Autorisation refusée sur GitHub (politique de l'organisation ?).",
                      "Authorization denied on GitHub (organization policy?).")
        case DeviceFlowError.unexpected(let msg):
            return tr("Connexion GitHub impossible : \(msg)", "Could not connect to GitHub: \(msg)")
        case is UsageParserError:
            return tr("Réponse sans bloc premium_interactions : format inattendu.",
                      "Response has no premium_interactions block: unexpected format.")
        default:
            return error.localizedDescription
        }
    }
}
