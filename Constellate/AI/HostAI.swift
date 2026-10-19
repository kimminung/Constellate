import ConstellateKit
import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Main-actor bridge the tools use to read the live graph. Tools are `nonisolated` (their `call` is `@concurrent`),
/// so every lookup hops here and returns plain strings.
@MainActor
final class HostToolContext {
    weak var model: AppModel?

    var graph: CodeGraph { model?.graph ?? SampleGraph.orbitNotes() }
    var language: HostLanguage { model?.language ?? .appDefault }

    func locate(_ query: String) -> HostReply {
        HeuristicHost.locate(query, in: graph, limit: 6, language: language)
    }

    func explain(_ rawID: String) -> HostReply {
        guard let id = resolve(rawID) else { return HostReply("Unknown node id \(rawID).") }
        var reply = HeuristicHost.explain(id, in: graph, language: language)
        // Role, coupling, cycle and relations by meaning ("Presents → SettingsView") — what the constellation shows.
        if let digest = model?.relationSummary(for: id), !digest.isEmpty {
            reply.text += "\n\nRelations: " + digest
        }
        if let node = graph.node(id) {
            let source = SourceProvider.source(for: node, in: graph, projectRoot: model?.projectRootURL)
            let preview = SourceProvider.previewLines(source, count: 14).joined(separator: "\n")
            reply.text += "\n\nCode preview:\n" + preview
        }
        return reply
    }

    func summarizeCluster(_ rawID: String) -> HostReply {
        guard let cluster = model?.clusters.first(where: { $0.id == rawID || $0.title == rawID }) else {
            let titles = (model?.clusters ?? []).prefix(10).map(\.title).joined(separator: ", ")
            return HostReply("Unknown cluster \(rawID). Known clusters: \(titles)")
        }
        return HeuristicHost.summarize(cluster, in: graph, language: language)
    }

    func reviewSource(_ rawID: String) -> HostReply {
        guard let id = resolve(rawID), let node = graph.node(id) else { return HostReply("Unknown node id \(rawID).") }
        let source = SourceProvider.source(for: node, in: graph, projectRoot: model?.projectRootURL)
        let clipped = SourceProvider.previewLines(source, count: 80).joined(separator: "\n")
        return HostReply("// \(node.path)\n" + clipped, nodeIDs: [id])
    }

    func tourCandidates() -> String {
        let g = graph
        let ids = TourBuilder().candidates(for: g, maxSteps: 10)
        return ids.enumerated().compactMap { index, id -> String? in
            guard let node = g.node(id) else { return nil }
            return "\(index + 1). \(node.name) [id: \(id.raw)] — \(node.kind.rawValue), \(node.layer.rawValue), \(node.lineCount) lines, referenced by \(g.fanIn(of: id))"
        }.joined(separator: "\n")
    }

    /// Accepts a raw id, a name, or a path and returns the best node.
    func resolve(_ raw: String) -> NodeID? {
        let g = graph
        let id = NodeID(raw)
        if g.node(id) != nil { return id }
        if let byPath = g.nodes.first(where: { $0.path == raw }) { return byPath.id }
        if let byName = g.nodes.first(where: { $0.name == raw }) { return byName.id }
        return CodeSearcher().search(raw, in: g, limit: 1).first?.nodeID
    }
}

#if canImport(FoundationModels)

// MARK: - Tools

nonisolated struct LocateCodeTool: Tool {
    let name = "locateCode"
    let description = "Find code in the project from a natural-language description in Korean or English (names, kinds like view/model/test, tags like @State, 'inherits X', 'in folder Y', and relations: 'presents X', 'observed by X', 'creates X', 'embedded in X', 'X를 띄우는 뷰'). Returns matching nodes with their ids."
    let context: HostToolContext

    @Generable
    struct Arguments {
        @Guide(description: "What to look for, e.g. 'views that use @State', '@State를 쓰는 뷰' or 'the note repository'")
        var query: String
    }

    @concurrent
    func call(arguments: Arguments) async throws -> String {
        let reply = await context.locate(arguments.query)
        let ids = reply.nodeIDs.map(\.raw).joined(separator: "\n")
        return reply.text + "\n\nnode ids:\n" + ids
    }
}

nonisolated struct ExplainNodeTool: Tool {
    let name = "explainNode"
    let description = "Describe one node of the code graph: kind, path, lines, tags, incoming/outgoing edges and a code preview. Pass a node id, a name or a path."
    let context: HostToolContext

    @Generable
    struct Arguments {
        @Guide(description: "Node id (preferred), symbol name or file path")
        var nodeID: String
    }

    @concurrent
    func call(arguments: Arguments) async throws -> String {
        await context.explain(arguments.nodeID).text
    }
}

nonisolated struct SummarizeClusterTool: Tool {
    let name = "summarizeCluster"
    let description = "Summarize a cluster (orb) of code: member counts, layers, imports. Pass the cluster id or title."
    let context: HostToolContext

    @Generable
    struct Arguments {
        @Guide(description: "Cluster id or title")
        var clusterID: String
    }

    @concurrent
    func call(arguments: Arguments) async throws -> String {
        await context.summarizeCluster(arguments.clusterID).text
    }
}

nonisolated struct ReviewNodeTool: Tool {
    let name = "reviewNode"
    let description = "Fetch the source code of a node so you can review it for correctness, clarity and Swift concurrency hygiene."
    let context: HostToolContext

    @Generable
    struct Arguments {
        @Guide(description: "Node id, symbol name or file path")
        var nodeID: String
    }

    @concurrent
    func call(arguments: Arguments) async throws -> String {
        await context.reviewSource(arguments.nodeID).text
    }
}

nonisolated struct PlanTourTool: Tool {
    let name = "planTour"
    let description = "List the ordered candidate stops (entry points, root types, busiest files) for a guided learning tour of the project."
    let context: HostToolContext

    @Generable
    struct Arguments {
        @Guide(description: "Optional focus, e.g. 'data flow' or 'UI'. Use an empty string for a general tour.")
        var focus: String
    }

    @concurrent
    func call(arguments: Arguments) async throws -> String {
        await context.tourCandidates()
    }
}

// MARK: - Structured answers

@Generable(description: "Answer to a 'find the code that …' request")
nonisolated struct LocateAnswer {
    @Guide(description: "One or two short sentences for the person, in the language the instructions ask for, grounded in the tool results.")
    var reply: String
    @Guide(description: "Node ids from the locateCode tool, best first.", .maximumCount(6))
    var nodeIDs: [String]
}

@Generable(description: "A guided tour of the project")
nonisolated struct TourAnswer {
    @Guide(description: "Short tour title, in the language the instructions ask for")
    var title: String
    @Guide(description: "Ordered tour stops", .maximumCount(8))
    var steps: [TourStopAnswer]
}

@Generable(description: "One stop of the tour")
nonisolated struct TourStopAnswer {
    @Guide(description: "Node id from planTour")
    var nodeID: String
    @Guide(description: "Short title")
    var title: String
    @Guide(description: "One or two sentences of narration for a newcomer, in the language the instructions ask for")
    var narration: String
}
#endif

// MARK: - HostAI

/// On-device code-review host. Wraps `LanguageModelSession` with tools and falls back to `HeuristicHost`.
/// Speaks the app's `HostLanguage` — Korean by default; switching rebuilds the session with new instructions.
@Observable
@MainActor
final class HostAI {

    enum Backend: Equatable {
        case appleIntelligence
        case heuristic(reason: String)

        func label(_ language: HostLanguage) -> String {
            switch self {
            case .appleIntelligence: language.pick("Apple Intelligence · 온디바이스", "Apple Intelligence · on-device")
            case .heuristic(let reason): language.pick("휴리스틱 호스트 · \(reason)", "Heuristic host · \(reason)")
            }
        }

        var isModel: Bool { self == .appleIntelligence }
    }

    private(set) var backend: Backend = .heuristic(reason: "…")
    private(set) var isThinking = false
    private(set) var lastError: String?
    /// False when the on-device model is up but does not list the chosen language; replies may then come back in English.
    private(set) var modelSupportsLanguage = true
    let context = HostToolContext()

    /// Reply language. Set by `AppModel.setLanguage`; the session is rebuilt so new instructions apply at once.
    var language: HostLanguage = .appDefault {
        didSet {
            guard language != oldValue else { return }
#if canImport(FoundationModels)
            session = nil
#endif
            refreshAvailability()
        }
    }

    /// "Apple Intelligence · 온디바이스" / "휴리스틱 호스트 · 모델 다운로드 중" in the current language.
    var backendLabel: String {
        var label = backend.label(language)
        if backend.isModel && !modelSupportsLanguage {
            label += language.pick(" (한국어 미지원 모델)", " (model lacks this language)")
        }
        return label
    }

    private static func instructions(for language: HostLanguage) -> String {
        switch language {
        case .korean:
            """
            당신은 공간형 코드 리뷰 회의 앱 Constellate의 호스트입니다. 팀은 소프트웨어 프로젝트의 3차원 "코드 별자리"를 보고 \
            있습니다: 파일·타입·멤버는 카드, 클러스터는 오브입니다. 반드시 한국어로, 간결하게 답하세요(리뷰를 요청받지 않는 한 \
            짧은 문장 세 개 이내). 답은 항상 도구 결과에 근거하세요: 코드를 찾을 때는 locateCode, 세부 정보는 explainNode, \
            오브는 summarizeCluster, 리뷰 전에는 reviewNode, 투어 계획 전에는 planTour를 사용하세요. 파일 이름이나 id를 \
            지어내지 마세요. 노드를 언급할 때는 id가 아니라 이름을 쓰고, 타입·함수 같은 코드 식별자는 번역하지 말고 원문 그대로 쓰세요.
            """
        case .english:
            """
            You are the host of Constellate, a spatial code-review meeting. The team is looking at a 3-D "constellation" of a \
            software project: files, types and members are cards, clusters are orbs. Answer in English, concisely (at most \
            three short sentences unless the person asks for a review). Always ground answers in tool results: use locateCode \
            to find code, explainNode for details, summarizeCluster for an orb, reviewNode before reviewing, planTour before \
            planning a tour. Never invent file names or ids. When you mention a node, use its name, not its id.
            """
        }
    }

#if canImport(FoundationModels)
    private var session: LanguageModelSession?
    private var turnCount = 0
#endif

    init() {
        refreshAvailability()
    }

    // MARK: Availability

    func refreshAvailability() {
#if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            backend = .appleIntelligence
            modelSupportsLanguage = model.supportedLanguages.contains { $0.languageCode?.identifier == language.rawValue }
            if session == nil { session = makeSession() }
        case .unavailable(let reason):
            session = nil
            backend = .heuristic(reason: Self.describe(reason, language))
        }
#else
        backend = .heuristic(reason: language.pick("이 플랫폼에서는 FoundationModels를 쓸 수 없음", "FoundationModels not available on this platform"))
#endif
    }

    func prewarm() {
#if canImport(FoundationModels)
        session?.prewarm()
#endif
    }

#if canImport(FoundationModels)
    private func makeSession() -> LanguageModelSession {
        let tools: [any Tool] = [
            LocateCodeTool(context: context),
            ExplainNodeTool(context: context),
            SummarizeClusterTool(context: context),
            ReviewNodeTool(context: context),
            PlanTourTool(context: context)
        ]
        turnCount = 0
        return LanguageModelSession(model: .default, tools: tools, instructions: Self.instructions(for: language))
    }

    /// Rebuilds the session when the transcript grows long so we never hit the context limit mid-answer.
    private func freshSessionIfNeeded() -> LanguageModelSession? {
        guard backend.isModel else { return nil }
        if session == nil || turnCount > 24 || (session?.transcript.count ?? 0) > 24 {
            session = makeSession()
        }
        turnCount += 1
        return session
    }

    private func recover(from error: Error) -> String {
        if let lmError = error as? LanguageModelError {
            switch lmError {
            case .contextSizeExceeded:
                session = makeSession()
                return language.pick("대화가 길어져서 새 세션을 시작했습니다.", "The conversation got long, so I started a fresh session.")
            case .guardrailViolation: return language.pick("그 요청은 도와드릴 수 없습니다.", "I can't help with that request.")
            case .refusal: return language.pick("모델이 답변을 거부해 휴리스틱 결과로 대신합니다.", "The model declined to answer; here is the heuristic result instead.")
            case .rateLimited: return language.pick("요청이 너무 잦습니다 — 잠시 후 다시 시도하세요.", "Rate limited — try again in a moment.")
            case .unsupportedLanguageOrLocale: return language.pick("온디바이스 모델이 이 언어를 지원하지 않습니다.", "That language isn't supported by the on-device model.")
            case .timeout: return language.pick("모델 응답 시간이 초과됐습니다.", "The model timed out.")
            default: return lmError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason, _ language: HostLanguage) -> String {
        switch reason {
        case .deviceNotEligible: language.pick("지원되지 않는 기기", "device not eligible")
        case .appleIntelligenceNotEnabled: language.pick("설정에서 Apple Intelligence 꺼짐", "Apple Intelligence is off in Settings")
        case .modelNotReady: language.pick("모델 다운로드 중", "model still downloading")
        @unknown default: language.pick("모델 사용 불가", "model unavailable")
        }
    }
#endif

    // MARK: - Requests

    /// Free-form chat. `situation` is a short description of what the user is looking at (docked cluster, selection).
    func chat(_ text: String, situation: String, graph: CodeGraph, clusters: [CodeCluster], docked: CodeCluster?) async -> HostReply {
        isThinking = true
        lastError = nil
        defer { isThinking = false }
#if canImport(FoundationModels)
        if let session = freshSessionIfNeeded() {
            do {
                let response = try await session.respond(to: prompt(text, situation: situation), options: GenerationOptions(temperature: 0.4, maximumResponseTokens: 500))
                let ids = Self.extractIDs(from: response.content, graph: graph)
                return HostReply(response.content, nodeIDs: ids)
            } catch {
                lastError = recover(from: error)
            }
        }
#endif
        return HeuristicHost.chat(text, graph: graph, clusters: clusters, docked: docked, language: language)
    }

    /// Streaming chat. `onPartial` receives the cumulative text at ≤ ~15 Hz; the final text is always delivered.
    func streamChat(_ text: String, situation: String, graph: CodeGraph, clusters: [CodeCluster], docked: CodeCluster?, onPartial: @escaping @MainActor (String) -> Void) async -> HostReply {
        isThinking = true
        lastError = nil
        defer { isThinking = false }
#if canImport(FoundationModels)
        if let session = freshSessionIfNeeded() {
            do {
                let stream = session.streamResponse(to: prompt(text, situation: situation), options: GenerationOptions(temperature: 0.4, maximumResponseTokens: 500))
                var latest = ""
                var lastEmit = ContinuousClock.now - .seconds(1)
                for try await snapshot in stream {
                    latest = snapshot.content
                    let now = ContinuousClock.now
                    if now - lastEmit >= .milliseconds(66) {
                        lastEmit = now
                        onPartial(latest)
                    }
                }
                let final = latest.trimmingCharacters(in: .whitespacesAndNewlines)
                if !final.isEmpty {
                    onPartial(final)
                    return HostReply(final, nodeIDs: Self.extractIDs(from: final, graph: graph))
                }
            } catch {
                lastError = recover(from: error)
            }
        }
#endif
        let reply = HeuristicHost.chat(text, graph: graph, clusters: clusters, docked: docked, language: language)
        onPartial(reply.text)
        return reply
    }

    /// Voice "find …" path: structured answer with node ids.
    func locate(_ query: String, graph: CodeGraph) async -> HostReply {
        isThinking = true
        lastError = nil
        defer { isThinking = false }
#if canImport(FoundationModels)
        if let session = freshSessionIfNeeded() {
            do {
                let response = try await session.respond(
                    to: language.pick(
                        "다음 설명에 맞는 코드를 찾으세요: \"\(query)\". locateCode 도구를 사용한 뒤 한국어로 답하세요.",
                        "Find the code that matches: \"\(query)\". Use the locateCode tool, then answer."),
                    generating: LocateAnswer.self,
                    options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 400)
                )
                let ids = response.content.nodeIDs.map { NodeID($0) }.filter { graph.node($0) != nil }
                if !ids.isEmpty { return HostReply(response.content.reply, nodeIDs: ids) }
            } catch {
                lastError = recover(from: error)
            }
        }
#endif
        return HeuristicHost.locate(query, in: graph, language: language)
    }

    func explain(_ id: NodeID, graph: CodeGraph) async -> HostReply {
        let fallback = HeuristicHost.explain(id, in: graph, language: language)
        guard let node = graph.node(id) else { return fallback }
        let request = language.pick(
            "\(node.name) (id: \(id.raw))을(를) 처음 보는 팀원에게 설명하세요. explainNode를 사용하세요.",
            "Explain \(node.name) (id: \(id.raw)) to a teammate who hasn't seen it. Use explainNode.")
        let reply = await chat(request, situation: "", graph: graph, clusters: [], docked: nil)
        return HostReply(reply.text, nodeIDs: [id] + reply.nodeIDs.filter { $0 != id })
    }

    func review(_ id: NodeID, graph: CodeGraph, projectRoot: URL?) async -> HostReply {
        guard let node = graph.node(id) else { return HostReply(language.pick("리뷰할 대상이 선택되지 않았습니다.", "Nothing selected to review.")) }
        let source = SourceProvider.source(for: node, in: graph, projectRoot: projectRoot)
        let fallback = HeuristicHost.review(id, source: source, in: graph, language: language)
#if canImport(FoundationModels)
        if backend.isModel {
            let request = language.pick(
                "\(node.name) (id: \(id.raw))을(를) 리뷰하세요. 먼저 reviewNode를 호출한 뒤 구체적인 지적 사항을 최대 4개 나열하세요.",
                "Review \(node.name) (id: \(id.raw)). Call reviewNode first, then list up to four concrete findings.")
            let reply = await chat(request, situation: "", graph: graph, clusters: [], docked: nil)
            if lastError == nil { return HostReply(reply.text, nodeIDs: [id]) }
        }
#endif
        return fallback
    }

    func summarize(_ cluster: CodeCluster, graph: CodeGraph) async -> HostReply {
        let fallback = HeuristicHost.summarize(cluster, in: graph, language: language)
#if canImport(FoundationModels)
        if backend.isModel {
            let request = language.pick(
                "클러스터 \"\(cluster.title)\" (id: \(cluster.id))을(를) 두 문장으로 요약하세요. summarizeCluster를 사용하세요.",
                "Summarize the cluster \"\(cluster.title)\" (id: \(cluster.id)) in two sentences. Use summarizeCluster.")
            let reply = await chat(request, situation: "", graph: graph, clusters: [], docked: nil)
            if lastError == nil { return HostReply(reply.text, nodeIDs: fallback.nodeIDs) }
        }
#endif
        return fallback
    }

    func planTour(graph: CodeGraph) async -> LearningTour {
        isThinking = true
        defer { isThinking = false }
        let fallback = HeuristicHost.tour(for: graph, language: language)
#if canImport(FoundationModels)
        if let session = freshSessionIfNeeded() {
            do {
                let response = try await session.respond(
                    to: language.pick(
                        "새 팀원을 위해 \(graph.projectName)의 가이드 투어를 계획하세요. planTour를 호출한 뒤 4~8개 정류장을 골라 각각 한국어로 해설하세요.",
                        "Plan a guided tour of \(graph.projectName) for a new team member. Call planTour, then pick 4–8 stops and narrate each."),
                    generating: TourAnswer.self,
                    options: GenerationOptions(temperature: 0.5, maximumResponseTokens: 900)
                )
                let steps = response.content.steps.compactMap { stop -> TourStep? in
                    guard let id = context.resolve(stop.nodeID) else { return nil }
                    return TourStep(nodeID: id, title: stop.title, narration: stop.narration)
                }
                if !steps.isEmpty { return LearningTour(title: response.content.title, steps: steps) }
            } catch {
                lastError = recover(from: error)
            }
        }
#endif
        return fallback
    }

    /// Wraps the question with the situation line in the session's language.
    private func prompt(_ text: String, situation: String) -> String {
        guard !situation.isEmpty else { return text }
        return language.pick("상황: \(situation)\n\n질문: \(text)", "Context: \(situation)\n\nQuestion: \(text)")
    }

    /// Finds node names mentioned in free text so the scene can highlight them.
    nonisolated static func extractIDs(from text: String, graph: CodeGraph, limit: Int = 6) -> [NodeID] {
        var found: [NodeID] = []
        for node in graph.nodes where node.kind.isSpatial && node.name.count >= 4 {
            if text.contains(node.name) {
                found.append(node.id)
                if found.count >= limit { break }
            }
        }
        return found
    }
}
