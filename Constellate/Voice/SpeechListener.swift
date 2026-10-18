import AVFoundation
import Foundation
import Observation
#if canImport(Speech)
import Speech
#endif

/// On-device speech recognition via `SpeechAnalyzer` + `SpeechTranscriber`, fed by `AVAudioEngine`.
/// Push-to-talk (`start`/`stop`) plus an optional wake word ("Constellate" / "콘스텔").
@Observable
@MainActor
final class SpeechListener {

    enum State: Equatable {
        case idle
        case preparing
        case listening
        case unavailable(String)

        var label: String {
            switch self {
            case .idle: "Mic off"
            case .preparing: "Preparing speech model…"
            case .listening: "Listening"
            case .unavailable(let reason): "Speech unavailable · \(reason)"
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var liveTranscript = ""
    /// When true, utterances are only forwarded after the wake word.
    var requiresWakeWord = false

    var onWakeWord: (() -> Void)?
    var onFinalUtterance: ((String) -> Void)?

    private var listenTask: Task<Void, Never>?
    private let engine = AVAudioEngine()
    private var tapBridge: AudioTapBridge?

    private static let wakeWords = ["constellate", "콘스텔레이트", "콘스텔", "콘스텔라"]

    var isActive: Bool { state == .listening || state == .preparing }

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
                state = .unavailable("microphone permission needed")
                return
            }
            let preferred = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
            let english = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US"))
            guard let locale = preferred ?? english else {
                state = .unavailable("no supported locale")
                return
            }
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                state = .unavailable("no compatible audio format")
                return
            }

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            let inputFormat = engine.inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0 else {
                state = .unavailable("no microphone input")
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
        state = .unavailable("Speech framework not available")
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
