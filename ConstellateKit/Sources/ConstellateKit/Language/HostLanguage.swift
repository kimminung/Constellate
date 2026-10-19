import Foundation

/// The language the host AI speaks, the speech recognizer listens in, and the app's chrome is shown in.
///
/// Korean is the primary language of Constellate; English is kept as an advanced option. The value is
/// persisted by the app and handed to every Kit builder that produces prose (`TourBuilder`,
/// `ClusterBuilder.heuristicSummary`) so fallbacks read naturally in both languages.
public enum HostLanguage: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case korean = "ko"
    case english = "en"

    public var id: String { rawValue }

    /// What a fresh install uses.
    public static let appDefault: HostLanguage = .korean

    /// The language's own name, for pickers ("한국어" / "English").
    public var nativeName: String {
        switch self {
        case .korean: "한국어"
        case .english: "English"
        }
    }

    /// Locale for speech recognition and date formatting.
    public var localeIdentifier: String {
        switch self {
        case .korean: "ko_KR"
        case .english: "en_US"
        }
    }

    /// BCP-47 tag for text-to-speech voices.
    public var voiceLanguage: String {
        switch self {
        case .korean: "ko-KR"
        case .english: "en-US"
        }
    }

    /// The other language (used as a fallback when a speech model is missing).
    public var fallback: HostLanguage {
        switch self {
        case .korean: .english
        case .english: .korean
        }
    }

    /// Picks the Korean or English copy of a string.
    @inlinable
    public func pick(_ korean: String, _ english: String) -> String {
        self == .korean ? korean : english
    }
}
