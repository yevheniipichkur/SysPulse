import Foundation

enum L10n {
    static func string(_ key: String, language: AppLanguage = .system, _ arguments: CVarArg...) -> String {
        string(key, language: language, arguments: arguments)
    }

    static func string(_ key: String, language: AppLanguage = .system, arguments: [CVarArg]) -> String {
        let format = localizedFormat(for: key, language: language)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: language.formatLocale, arguments: arguments)
    }

    private static func localizedFormat(for key: String, language: AppLanguage) -> String {
        guard let resource = language.localizationResource,
              let path = Bundle.main.path(forResource: resource, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }

        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

private extension AppLanguage {
    var localizationResource: String? {
        switch self {
        case .system:
            nil
        case .english:
            "en"
        case .ukrainian:
            "uk"
        case .russian:
            "ru"
        case .polish:
            "pl"
        }
    }

    var formatLocale: Locale {
        switch self {
        case .system:
            .autoupdatingCurrent
        case .english:
            Locale(identifier: "en")
        case .ukrainian:
            Locale(identifier: "uk")
        case .russian:
            Locale(identifier: "ru")
        case .polish:
            Locale(identifier: "pl")
        }
    }
}
