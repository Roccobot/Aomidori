import Foundation

/// Localized UI text. English is the development language; keys and translations live in
/// `Resources/en.lproj` and `Resources/it.lproj` (`Localizable.strings`). The app follows the
/// system language and falls back to English.
enum L10n {
    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: arguments)
    }
}
