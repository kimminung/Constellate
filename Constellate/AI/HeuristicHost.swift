import ConstellateKit
import Foundation

/// Reply from the host AI (either backend). `nodeIDs` are the nodes the answer is grounded in.
nonisolated struct HostReply: Sendable, Hashable {
    var text: String
    var nodeIDs: [NodeID]

    init(_ text: String, nodeIDs: [NodeID] = []) {
        self.text = text
        self.nodeIDs = nodeIDs
    }
}

/// Deterministic fallback used when Apple Intelligence is unavailable (simulators, older devices).
/// Every feature keeps working; only the prose gets plainer.
nonisolated enum HeuristicHost {

    static func locate(_ query: String, in graph: CodeGraph, limit: Int = 6) -> HostReply {
        let hits = CodeSearcher().search(query, in: graph, limit: limit)
        guard !hits.isEmpty else {
            return HostReply("I couldn't find anything matching \"\(query)\". Try a type name, a folder, or a tag like @State.")
        }
        var lines = ["Found \(hits.count) match\(hits.count == 1 ? "" : "es") for \"\(query)\":"]
        for hit in hits {
            guard let node = graph.node(hit.nodeID) else { continue }
            lines.append("• \(node.name) (\(node.kind.rawValue), \(node.layer.rawValue)) — \(hit.reason)")
        }
        return HostReply(lines.joined(separator: "\n"), nodeIDs: hits.map(\.nodeID))
    }

    static func explain(_ id: NodeID, in graph: CodeGraph) -> HostReply {
        guard let node = graph.node(id) else { return HostReply("That node is no longer in the graph.") }
        var parts: [String] = []
        parts.append("\(node.name) is a \(describe(node.kind)) in the \(node.layer.rawValue) layer, at \(node.path)")
        if let lines = node.lines { parts.append("lines \(lines.start)–\(lines.end)") } else if node.lineCount > 0 { parts.append("\(node.lineCount) lines") }
        if !node.tags.isEmpty { parts.append("tags: " + node.tags.sorted().joined(separator: ", ")) }
        let out = graph.outgoing(from: id)
        let inc = graph.incoming(to: id)
        if !out.isEmpty {
            let names = out.prefix(5).compactMap { graph.node($0.to)?.name }
            parts.append("it \(verb(out)) \(names.joined(separator: ", "))")
        }
        if !inc.isEmpty {
            parts.append("\(inc.count) other node\(inc.count == 1 ? "" : "s") depend on it")
        }
        let children = graph.children(of: id)
        if !children.isEmpty {
            parts.append("contains " + children.prefix(6).map(\.name).joined(separator: ", ") + (children.count > 6 ? " and \(children.count - 6) more" : ""))
        }
        let related = out.map(\.to) + inc.map(\.from)
        return HostReply(parts.joined(separator: "; ") + ".", nodeIDs: [id] + Array(related.prefix(5)))
    }

    static func summarize(_ cluster: CodeCluster, in graph: CodeGraph) -> HostReply {
        var text = ClusterBuilder.heuristicSummary(for: cluster, in: graph)
        let members = cluster.memberNodeIDs.compactMap(graph.node)
        let views = members.filter { $0.tags.contains("SwiftUI.View") }.count
        if views > 0 { text += " \(views) SwiftUI view\(views == 1 ? "" : "s")." }
        let imports = Set(members.flatMap { graph.outgoing(from: $0.id, kinds: [.imports]).compactMap { graph.node($0.to)?.name } })
        if !imports.isEmpty { text += " Imports " + imports.sorted().prefix(5).joined(separator: ", ") + "." }
        return HostReply(text, nodeIDs: Array(cluster.memberNodeIDs.prefix(6)))
    }

    static func review(_ id: NodeID, source: String, in graph: CodeGraph) -> HostReply {
        guard let node = graph.node(id) else { return HostReply("Nothing to review.") }
        var notes: [String] = []
        let lineCount = source.split(whereSeparator: \.isNewline).count
        if lineCount > 300 { notes.append("At \(lineCount) lines this \(describe(node.kind)) is large; consider splitting it.") }
        if source.contains("!") && source.contains("try!") { notes.append("`try!` found — prefer `do/catch` or `try?`.") }
        if source.contains("as!") { notes.append("Forced cast `as!` found — guard with `as?`.") }
        if source.contains("DispatchQueue") { notes.append("GCD usage — consider structured concurrency.") }
        if source.contains("@State") && source.contains("class ") { notes.append("`@State` on a class-typed property — make sure the model is `@Observable`.") }
        let incoming = graph.incoming(to: id).count
        if incoming > 12 { notes.append("\(incoming) dependents — changes here ripple widely; add tests.") }
        if notes.isEmpty { notes.append("No obvious issues from a structural pass over \(node.name). Review the logic by hand.") }
        return HostReply(notes.joined(separator: " "), nodeIDs: [id])
    }

    static func tour(for graph: CodeGraph) -> LearningTour {
        TourBuilder().tour(for: graph)
    }

    /// Catch-all chat answer: tries a search first, then describes the project.
    static func chat(_ text: String, graph: CodeGraph, clusters: [CodeCluster], docked: CodeCluster?) -> HostReply {
        if let docked {
            let s = summarize(docked, in: graph)
            return HostReply("From inside \(docked.title): " + s.text, nodeIDs: s.nodeIDs)
        }
        let hits = CodeSearcher().search(text, in: graph, limit: 4)
        if !hits.isEmpty { return locate(text, in: graph, limit: 4) }
        return HostReply("\(graph.projectName) has \(graph.fileCount) files and \(graph.totalLines) lines in \(clusters.count) clusters. Ask me to find, explain, review or tour something.")
    }

    // MARK: - helpers

    static func describe(_ kind: NodeKind) -> String {
        switch kind {
        case .module: "module"
        case .folder: "folder"
        case .file: "source file"
        case .type: "type"
        case .extensionDecl: "extension"
        case .function: "function"
        case .property: "property"
        }
    }

    private static func verb(_ edges: [CodeEdge]) -> String {
        let kinds = Set(edges.map(\.kind))
        if kinds == [.imports] { return "imports" }
        if kinds == [.inherits] { return "inherits from / conforms to" }
        if kinds == [.calls] { return "calls" }
        return "references"
    }
}
