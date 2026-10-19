import AVFoundation
import ConstellateKit
import Foundation
import Observation
#if canImport(Speech)
import Speech
#endif

/// On-device speech recognition via `SpeechAnalyzer` + `SpeechTranscriber`, fed by `AVAudioEngine`.
/// Push-to-talk (`start`/`stop`) plus an optional wake word ("콘스텔" / "Constellate").
/// Listens in the app's `HostLanguage` (Korean by default) and falls back to the other language's model.
@Observable
@MainActor
final class SpeechListener {

    enum State: Equatable {
        case idle
        case preparing
        case listening
        case unavailable(String)

        func label(_ language: HostLanguage) -> String {
            switch self {
            case .idle: language.pick("마이크 꺼짐", "Mic off")
            case .preparing: language.pick("음성 모델 준비 중…", "Preparing speech model…")
            case .listening: language.pick("듣는 중", "Listening")
            case .unavailable(let reason): language.pick("음성 인식 불가 · \(reason)", "Speech unavailable · \(reason)")
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var liveTranscript = ""
    /// When true, utterances are only forwarded after the wake word.
    var requiresWakeWord = false
    /// Recognition language. Changing it while listening restarts the session with the new model.
    var language: HostLanguage = .appDefault {
        didSet {
            guard language != oldValue, isActive else { return }
            stop()
            start()
        }
    }

    var onWakeWord: (() -> Void)?
    var onFinalUtterance: ((String) -> Void)?

    private var listenTask: Task<Void, Never>?
    private let engine = AVAudioEngine()
    private var tapBridge: AudioTapBridge?

    private static let wakeWords = ["constellate", "콘스텔레이트", "콘스텔", "콘스텔라"]

    var isActive: Bool { state == .listening || state == .preparing }

    /// Status text in the current language (tooltips, accessibility).
    var stateLabel: String { state.label(language) }

    func toggle() {
        if isActive { stop() } else { start() }
    }

    func start() {
        guard listenTask == nil else { return }
        state = .preparing
        liveTranscript = ""
        listenTask = Task { await runSession() }
    }

    func stop() {
        listenTask?.cancel()
        listenTask = nil
        tearDownAudio()
        if case .unavailable = state { return }
        state = .idle
    }

    private func tearDownAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        tapBridge?.finish()
        tapBridge = nil
    }

    // MARK: - Session

    private func runSession() async {
        defer { listenTask = nil }
#if canImport(Speech)
        do {
            guard await AVAudioApplication.requestRecordPermission() else {
                state = .unavailable(language.pick("마이크 권한이 필요합니다", "microphone permission needed"))
                return
            }
            // Preferred language first, then the other one, then whatever the device speaks.
            let primary = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.localeIdentifier))
            let secondary = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.fallback.localeIdentifier))
            let device = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
            guard let locale = primary ?? secondary ?? device else {
                state = .unavailable(language.pick("지원되는 언어가 없습니다", "no supported locale"))
                return
            }
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                state = .unavailable(language.pick("호환되는 오디오 형식이 없습니다", "no compatible audio format"))
                return
            }

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            let inputFormat = engine.inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0 else {
                state = .unavailable(language.pick("마이크 입력이 없습니다", "no microphone input"))
                return
            }
            let bridge = AudioTapBridge(inputFormat: inputFormat, outputFormat: analyzerFormat, continuation: continuation)
            tapBridge = bridge
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
                bridge.handle(buffer)
            }
            engine.prepare()
            try engine.start()
            try Task.checkCancellation()
            state = .listening

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.consumeResults(from: transcriber) }
                group.addTask {
                    if let last = try await analyzer.analyzeSequence(stream) {
                        try await analyzer.finalizeAndFinish(through: last)
                    }
                }
                try await group.waitForAll()
            }
            if case .listening = state { state = .idle }
        } catch is CancellationError {
            if case .listening = state { state = .idle }
        } catch {
            state = .unavailable(error.localizedDescription)
            tearDownAudio()
        }
#else
        state = .unavailable(language.pick("Speech 프레임워크를 사용할 수 없습니다", "Speech framework not available"))
#endif
    }

#if canImport(Speech)
    private func consumeResults(from transcriber: SpeechTranscriber) async throws {
        for try await result in transcriber.results {
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if result.isFinal {
                liveTranscript = ""
                handleFinal(text)
            } else {
                liveTranscript = text
            }
        }
    }
#endif

    /// Detects the wake word and forwards the remaining command.
    private func handleFinal(_ text: String) {
        guard !text.isEmpty else { return }
        let lower = text.lowercased()
        var command = text
        var heardWake = false
        if let wake = Self.wakeWords.first(where: { lower.contains($0) }), let range = lower.range(of: wake) {
            heardWake = true
            onWakeWord?()
            let offset = lower.distance(from: lower.startIndex, to: range.upperBound)
            if let start = text.index(text.startIndex, offsetBy: offset, limitedBy: text.endIndex) {
                command = String(text[start...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?아야"))
            }
        }
        if requiresWakeWord && !heardWake { return }
        guard command.count >= 2 else { return }
        onFinalUtterance?(command)
    }
}

/// Lives on the audio render thread: converts mic buffers to the analyzer's format and yields them.
nonisolated final class AudioTapBridge: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
#if canImport(Speech)
    private let continuation: AsyncStream<AnalyzerInput>.Continuation

    init(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.outputFormat = outputFormat
        self.continuation = continuation
        self.converter = inputFormat == outputFormat ? nil : AVAudioConverter(from: inputFormat, to: outputFormat)
    }

    func handle(_ buffer: AVAudioPCMBuffer) {
        guard let converter else {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var conversionError: NSError?
        converter.convert(to: out, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, out.frameLength > 0 else { return }
        continuation.yield(AnalyzerInput(buffer: out))
    }

    func finish() { continuation.finish() }
#else
    init(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
        self.converter = nil
    }
    func handle(_ buffer: AVAudioPCMBuffer) {}
    func finish() {}
#endif
}
