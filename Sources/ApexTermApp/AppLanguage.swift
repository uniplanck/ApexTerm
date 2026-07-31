import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case japanese = "ja"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case korean = "ko"

    static let defaultsKey = "apexterm.language"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            .autoupdatingCurrent
        default:
            Locale(identifier: rawValue)
        }
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .system: "System Default"
        case .english: "English"
        case .japanese: "Japanese"
        case .chineseSimplified: "Chinese (Simplified)"
        case .chineseTraditional: "Chinese (Traditional)"
        case .korean: "Korean"
        }
    }

    static func resolve(_ rawValue: String) -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? .system
    }
}
