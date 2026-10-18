import ConstellateKit
import Foundation

/// What the person asked for, parsed from a transcript. Everything unrecognised becomes `.ask`.
enum VoiceIntent: Equatable, Sendable {
    case find(query: String)
    case explain(query: String?)
    case dock(query: String?)
    case undock
    case theme(hue: Double?, dark: Bool)
    case tour
    case time(dial: Float)
    case ask(text: String)
}

/// Keyword router (English + Korean). Deliberately simple and deterministic.
nonisolated struct VoiceCommandRouter {

    private static let findWords = ["찾아", "find", "where is", "where's", "show me", "출두", "locate", "search", "보여"]
    private static let explainWords = ["설명", "explain", "what does", "what is", "뭐야", "describe"]
    private static let dockWords = ["들어가", "dock", "go into", "enter", "join"]
    private static let undockWords = ["나와", "come out", "undock", "leave", "detach", "release"]
    private static let tourWords = ["투어", "tour", "가르쳐", "teach me", "walk me through", "guide"]
    private static let themeWords = ["어둡게", "dark", "색", "color", "colour", "theme", "테마", "hue"]
    private static let hueWords: [(String, Double)] = [
        ("red", 0), ("빨강", 0), ("빨간", 0),
        ("orange", 30), ("주황", 30), ("ember", 20),
        ("yellow", 55), ("노랑", 55), ("노란", 55),
        ("green", 140), ("초록", 140), ("moss", 150),
        ("teal", 175), ("청록", 175),
        ("blue", 215), ("파랑", 215), ("파란", 215), ("ocean", 210),
        ("indigo", 255), ("남색", 255),
        ("purple", 275), ("보라", 275), ("nebula", 275), ("violet", 280),
        ("pink", 320), ("분홍", 320)
    ]

    func parse(_ raw: String) -> VoiceIntent {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        guard !lower.isEmpty else { return .ask(text: text) }

        if Self.undockWords.contains(where: lower.contains) { return .undock }
        if Self.tourWords.contains(where: lower.contains) { return .tour }

        if lower.contains("최근") || lower.contains("recent") || lower.contains("newest") || lower.contains("latest") { return .time(dial: 1) }
        if lower.contains("오래된") || lower.contains("oldest") || lower.contains("old code") { return .time(dial: -1) }
        if lower.contains("reset time") || lower.contains("시간 초기화") || lower.contains("time dial off") { return .time(dial: 0) }

        if Self.themeWords.contains(where: lower.contains) {
            if lower.contains("dark") || lower.contains("어둡") { return .theme(hue: nil, dark: true) }
            if let hue = Self.hueWords.first(where: { lower.contains($0.0) })?.1 { return .theme(hue: hue, dark: false) }
            if lower.contains("color") || lower.contains("colour") || lower.contains("색") || lower.contains("테마") { return .theme(hue: nil, dark: true) }
        }

        if let word = Self.dockWords.first(where: lower.contains) {
            return .dock(query: Self.strip(text, lower: lower, word: word))
        }
        if let word = Self.explainWords.first(where: lower.contains) {
            return .explain(query: Self.strip(text, lower: lower, word: word))
        }
        if let word = Self.findWords.first(where: lower.contains) {
            let q = Self.strip(text, lower: lower, word: word) ?? text
            return .find(query: q)
        }
        return .ask(text: text)
    }

    /// Removes the trigger word and filler so the remainder can be used as a search query.
    private static func strip(_ text: String, lower: String, word: String) -> String? {
        var result = lower.replacingOccurrences(of: word, with: " ")
        for filler in ["please", "the code", "code", "for me", "me", "줘", "주세요", "해줘", "하는", "을", "를", "좀", "the", "that", "which", "a "] {
            result = result.replacingOccurrences(of: filler, with: " ")
        }
        let cleaned = result.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
        return cleaned.isEmpty ? nil : cleaned
    }
}
