import Foundation

enum Loc {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }

    static var prefersChinese: Bool {
        Locale.preferredLanguages.contains { $0.hasPrefix("zh") }
    }
}
