import Foundation

enum Localization { static let bundle = Bundle.module }

// Use the same native resource bundle for AppKit, SwiftUI and diagnostics.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = NSLocalizedString(key, bundle: Localization.bundle, comment: "")
    return arguments.isEmpty ? format : String(format: format, locale: Locale.current, arguments: arguments)
}
