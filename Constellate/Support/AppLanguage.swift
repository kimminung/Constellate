import ConstellateKit
import Foundation
import Observation

/// App-wide language (persisted). Korean is the default; English is an advanced option in Settings.
///
/// One observable source of truth so every view re-renders when the language flips. `AppModel.setLanguage`
/// is the only writer — it also retargets the host AI session and the speech recognizer.
@Observable
@MainActor
final class LanguageSetting {
    static let shared = LanguageSetting()
    private static let key = "appLanguage"

    var language: HostLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    private init() {
        language = UserDefaults.standard.string(forKey: Self.key).flatMap(HostLanguage.init(rawValue:)) ?? .appDefault
    }
}

/// Picks the Korean or English copy for the current app language. Views call this inside `body`, so the
/// observation system tracks the read and refreshes the view when the setting changes.
@MainActor
func L(_ korean: String, _ english: String) -> String {
    LanguageSetting.shared.language.pick(korean, english)
}

/// Theme preset names are identity keys ("Ocean" — the picker matches on them); show them in Korean when the app is.
@MainActor
func themeDisplayName(_ name: String) -> String {
    switch name {
    case "Dark": L("다크", "Dark")
    case "Ocean": L("오션", "Ocean")
    case "Moss": L("모스", "Moss")
    case "Ember": L("엠버", "Ember")
    case "Nebula": L("네뷸라", "Nebula")
    default: name
    }
}
