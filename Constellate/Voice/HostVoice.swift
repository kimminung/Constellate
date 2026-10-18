import Foundation
import Observation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Text-to-speech for the host's final replies. Presence "speaking" follows the real utterance via the
/// synthesizer delegate (`onStart` / `onFinish`) instead of an estimated duration.
@Observable
@MainActor
final class HostVoice: NSObject {
    private(set) var isSpeaking = false
    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?

#if canImport(AVFoundation)
    private let synthesizer = AVSpeechSynthesizer()
    var isAvailable: Bool { true }
#else
    var isAvailable: Bool { false }
#endif

    override init() {
        super.init()
#if canImport(AVFoundation)
        synthesizer.delegate = self
#endif
    }

    /// Speaks `text` after stripping markdown and node ids. Korean if the text contains Hangul, else English.
    func speak(_ text: String) {
#if canImport(AVFoundation)
        stop()
        let spoken = Self.cleaned(text)
        guard !spoken.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: spoken)
        let language = Self.containsHangul(spoken) ? "ko-KR" : "en-US"
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        utterance.pitchMultiplier = 1.0
        utterance.prefersAssistiveTechnologySettings = false
        synthesizer.speak(utterance)
#endif
    }

    func stop() {
#if canImport(AVFoundation)
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
#endif
        if isSpeaking {
            isSpeaking = false
            onFinish?()
        }
    }

    // MARK: - Text clean-up

    nonisolated static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x1100...0x11FF).contains($0.value) || (0x3130...0x318F).contains($0.value) }
    }

    /// Removes markdown decoration, code fences, bracketed ids and path-like tokens so the voice reads prose only.
    nonisolated static func cleaned(_ text: String) -> String {
        var s = text
        let patterns: [(String, String)] = [
            ("```[\\s\\S]*?```", " "),                     // code fences
            ("\\[id:[^\\]]*\\]", ""),                      // [id: …]
            ("\\(id[: ][^)]*\\)", ""),                     // (id …)
            ("\\bnode ids?:[\\s\\S]*$", ""),               // trailing id lists from tools
            ("`([^`]*)`", "$1"),                           // inline code
            ("[*_#>]+", ""),                               // emphasis / headings / quotes
            ("\\S+/\\S+\\.(swift|py|js|ts|kt|java|go|rs|m|h)\\b", "file"), // paths
            ("\\s{2,}", " ")
        ]
        for (pattern, replacement) in patterns {
            s = s.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if canImport(AVFoundation)
extension HostVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
            self.onStart?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.isSpeaking else { return }
            self.isSpeaking = false
            self.onFinish?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.isSpeaking else { return }
            self.isSpeaking = false
            self.onFinish?()
        }
    }
}
#endif
