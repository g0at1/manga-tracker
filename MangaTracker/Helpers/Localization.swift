import Foundation
import SwiftUI

/// Languages the UI can be shown in, picked in Ustawienia.
enum AppLanguage: String, CaseIterable, Identifiable {
    case polish = "pl"
    case english = "en"

    static let storageKey = "appLanguage"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .polish: "Polski"
        case .english: "English"
        }
    }

    var locale: Locale {
        switch self {
        case .polish: Locale(identifier: "pl_PL")
        case .english: Locale(identifier: "en_US")
        }
    }

    /// The `.lproj` bundle holding this language's strings.
    var bundle: Bundle {
        Bundle.main.path(forResource: rawValue, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
    }

    static var current: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return AppLanguage(rawValue: stored) ?? .polish
    }
}

/// Looks up a catalog string in the selected language. SwiftUI views localize
/// their literals on their own; this is for strings built in code (toasts,
/// computed labels, pasteboard text).
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let language = AppLanguage.current
    let format = language.bundle.localizedString(forKey: key, value: key, table: nil)
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: language.locale, arguments: arguments)
}
