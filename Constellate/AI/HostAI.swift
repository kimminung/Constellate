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

    func locate(_ query: String) -> HostReply {
        HeuristicHost.locate(query, in: graph, limit: 6)
    }

    func explain(_ rawID: String) -> HostReply {
        guard let id = resolve(rawID) else { return HostReply("Unknown node id \(rawID).") }
        var reply = HeuristicHost.explain(id, in: graph)
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
        return HeuristicHost.summarize(cluster, in: graph)
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
    let description = "Find code in the project from a natural-language description (names, kinds like view/model/test, tags like @State, 'inherits X', 'in folder Y'). Returns matching nodes with their ids."
    let context: HostToolContext

    @Generable
    struct Arguments {
        @Guide(description: "What to look for, e.g. 'views that use @State' or 'the note repository'")
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
    @Guide(description: "One or two short sentences for the person, grounded in the tool results.")
    var reply: String
    @Guide(description: "Node ids from the locateCode tool, best first.", .maximumCount(6))
    var nodeIDs: [String]
}

@Generable(description: "A guided tour of the project")
nonisolated struct TourAnswer {
    @Guide(description: "Short tour title")
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
    @Guide(description: "One or two sentences of narration for a newcomer")
    var narration: String
}
#endif

// MARK: - HostAI

/// On-device code-review host. Wraps `LanguageModelSession` with tools and falls back to `HeuristicHost`.
@Observable
@MainActor
final class HostAI {

    enum Backend: Equatable {
        case appleIntelligence
        case heuristic(reason: String)

        var label: String {
            switch self {
            case .appleIntelligence: "Apple Intelligence · on-device"
            case .heuristic(let reason): "Heuristic host · \(reason)"
            }
        }

        var isModel: Bool { self == .appleIntelligence }
    }

    private(set) var backend: Backend = .heuristic(reason: "checking")
    private(set) var isThinking = false
    private(set) var lastError: String?
    let context = HostToolContext()

    private static let instructions = """
    You are the host of Constellate, a spatial code-review meeting. The team is looking at a 3-D "constellation" of a \
    software project: files, types and members are cards, clusters are orbs. Answer in English, concisely (at most \
    three short sentences unless the person asks for a review). Always ground answers in tool results: use locateCode \
    to find code, explainNode for details, summarizeCluster for an orb, reviewNode before reviewing, planTour before \
    planning a tour. Never invent file names or ids. When you mention a node, use its name, not its id.
    """

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
            if session == nil { session = makeSession() }
        case .unavailable(let reason):
            session = nil
            backend = .heuristic(reason: Self.describe(reason))
        }
#else
        backend = .heuristic(reason: "FoundationModels not available on this platform")
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
        return LanguageModelSession(model: .default, tools: tools, instructions: Self.instructions)
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
                return "The conversation got long, so I started a fresh session."
            case .guardrailViolation: return "I can't help with that request."
            case .refusal: return "The model declined to answer; here is the heuristic result instead."
            case .rateLimited: return "Rate limited — try again in a moment."
            case .unsupportedLanguageOrLocale: return "That language isn't supported by the on-device model."
            case .timeout: return "The model timed out."
            default: return lmError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: "device not eligible"
        case .appleIntelligenceNotEnabled: "Apple Intelligence is off in Settings"
        case .modelNotReady: "model still downloading"
        @unknown default: "model unavailable"
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
                let prompt = situation.isEmpty ? text : "Context: \(situation)\n\nQuestion: \(text)"
                let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.4, maximumResponseTokens: 500))
                let ids = Self.extractIDs(from: response.content, graph: graph)
                return HostReply(response.content, nodeIDs: ids)
            } catch {
                lastError = recover(from: error)
            }
        }
#endif
        return HeuristicHost.chat(text, graph: graph, clusters: clusters, docked: docked)
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
                    to: "Find the code that matches: \"\(query)\". Use the locateCode tool, then answer.",
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
        return HeuristicHost.locate(query, in: graph)
    }

    func explain(_ id: NodeID, graph: CodeGraph) async -> HostReply {
        let fallback = HeuristicHost.explain(id, in: graph)
        guard let node = graph.node(id) else { return fallback }
        let reply = await chat("Explain \(node.name) (id: \(id.raw)) to a teammate who hasn't seen it. Use explainNode.", situation: "", graph: graph, clusters: [], docked: nil)
        return HostReply(reply.text, nodeIDs: [id] + reply.nodeIDs.filter { $0 != id })
    }

    func review(_ id: NodeID, graph: CodeGraph, projectRoot: URL?) async -> HostReply {
        guard let node = graph.node(id) else { return HostReply("Nothing selected to review.") }
        let source = SourceProvider.source(for: node, in: graph, projectRoot: projectRoot)
        let fallback = HeuristicHost.review(id, source: source, in: graph)
#if canImport(FoundationModels)
        if backend.isModel {
            let reply = await chat("Review \(node.name) (id: \(id.raw)). Call reviewNode first, then list up to four concrete findings.", situation: "", graph: graph, clusters: [], docked: nil)
            if lastError == nil { return HostReply(reply.text, nodeIDs: [id]) }
        }
#endif
        return fallback
    }

    func summarize(_ cluster: CodeCluster, graph: CodeGraph) async -> HostReply {
        let fallback = HeuristicHost.summarize(cluster, in: graph)
#if canImport(FoundationModels)
        if backend.isModel {
            let reply = await chat("Summarize the cluster \"\(cluster.title)\" (id: \(cluster.id)) in two sentences. Use summarizeCluster.", situation: "", graph: graph, clusters: [], docked: nil)
            if lastError == nil { return HostReply(reply.text, nodeIDs: fallback.nodeIDs) }
        }
#endif
        return fallback
    }

    func planTour(graph: CodeGraph) async -> LearningTour {
        isThinking = true
        defer { isThinking = false }
        let fallback = HeuristicHost.tour(for: graph)
#if canImport(FoundationModels)
        if let session = freshSessionIfNeeded() {
            do {
                let response = try await session.respond(
                    to: "Plan a guided tour of \(graph.projectName) for a new team member. Call planTour, then pick 4–8 stops and narrate each.",
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
