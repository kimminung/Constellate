import Foundation

/// Builds a heuristic learning tour when the AI is unavailable, and provides the ordered candidate list
/// the AI narrates when it is.
///
/// Order: the `@main` entry point → the largest root-level folders → the most referenced SwiftUI views →
/// the busiest domain / data files → the tests. Steps are de-duplicated and capped at `maxSteps`.
/// Narration is English; the app localises through the AI.
public struct TourBuilder: Sendable {
    public init() {}

    public func tour(for graph: CodeGraph, maxSteps: Int = 8) -> LearningTour {
        let ids = candidates(for: graph, maxSteps: maxSteps)
        let steps = ids.compactMap { id -> TourStep? in
            guard let node = graph.node(id) else { return nil }
            return TourStep(nodeID: id, title: title(for: node), narration: narration(for: node, in: graph))
        }
        return LearningTour(title: "\(graph.projectName) overview", steps: steps)
    }

    /// Ordered, de-duplicated node ids the tour visits (used by the AI when it writes its own narration).
    public func candidates(for graph: CodeGraph, maxSteps: Int) -> [NodeID] {
        var out: [NodeID] = []
        var seen: Set<NodeID> = []
        func add(_ id: NodeID) {
            guard out.count < maxSteps, seen.insert(id).inserted else { return }
            out.append(id)
        }

        // 1. Entry point (type preferred, then file).
        if let entry = graph.entryPoints().first {
            add(entry.id)
        } else if let root = graph.root {
            add(root.id)
        }

        // 2. Root-level folders by subtree size.
        if let root = graph.root {
            var level = root
            for _ in 0..<2 {
                let kids = graph.children(of: level.id)
                let folders = kids.filter { $0.kind == .folder }
                if folders.count == 1, !kids.contains(where: { $0.kind == .file }), let only = folders.first { level = only } else { break }
            }
            let folders = graph.children(of: level.id)
                .filter { $0.kind == .folder && $0.layer != .test }
                .map { ($0, graph.subtreeLines(of: $0.id)) }
                .sorted { a, b in a.1 != b.1 ? a.1 > b.1 : a.0.name < b.0.name }
            for (folder, _) in folders.prefix(3) { add(folder.id) }
        }

        // 3. SwiftUI views with most incoming references.
        let views = graph.nodes
            .filter { $0.kind == .type && $0.tags.contains("SwiftUI.View") && !$0.tags.contains("entry-point") }
            .map { ($0, viewFanIn($0, in: graph)) }
            .sorted { a, b in a.1 != b.1 ? a.1 > b.1 : a.0.name < b.0.name }
        for (view, _) in views.prefix(2) { add(view.id) }

        // 4. Busiest domain / data files.
        for file in graph.busiestFiles(limit: 2, layers: [.domain, .data]) { add(file.id) }

        // 5. Tests.
        if let testFolder = graph.nodes.first(where: { $0.kind == .folder && $0.layer == .test }) {
            add(testFolder.id)
        } else if let testFile = graph.nodes(ofKind: .file).filter({ $0.layer == .test || $0.tags.contains("test") }).sorted(by: { $0.lineCount > $1.lineCount }).first {
            add(testFile.id)
        }

        // Fill with the largest remaining files if the graph is small.
        if out.count < min(maxSteps, 3) {
            for file in graph.busiestFiles(limit: maxSteps) { add(file.id) }
        }
        return out
    }

    // MARK: - Narration

    /// References to the view itself plus to the file that declares it.
    private func viewFanIn(_ node: CodeNode, in graph: CodeGraph) -> Int {
        var n = graph.fanIn(of: node.id)
        if let file = graph.file(containing: node.id), file.id != node.id { n += graph.fanIn(of: file.id) }
        return n
    }

    private func title(for node: CodeNode) -> String {
        switch node.kind {
        case .module: "Project: \(node.name)"
        case .folder: "\(node.name)/"
        case .file: node.name
        case .type: node.tags.contains("entry-point") ? "Entry point: \(node.name)" : node.name
        case .extensionDecl: "extension \(node.name)"
        case .function: "\(node.name)()"
        case .property: node.name
        }
    }

    private func narration(for node: CodeNode, in graph: CodeGraph) -> String {
        switch node.kind {
        case .module:
            let s = graph.stats()
            return "\(node.name) has \(s.fileCount) files and \(s.totalLines) lines. We'll start from the top and work down through its layers."
        case .folder:
            let files = graph.subtree(of: node.id).filter { $0.kind == .file }
            let lines = files.reduce(0) { $0 + $1.lineCount }
            var counts: [ArchitectureLayer: Int] = [:]
            for f in files { counts[f.layer, default: 0] += 1 }
            let layer = counts.max { $0.value < $1.value }?.key ?? node.layer
            if node.layer == .test {
                return "The \(node.name) folder holds \(files.count) test files; they are the safest place to learn how the pieces are meant to be used."
            }
            return "The \(node.name) folder holds \(files.count) files and \(lines) lines, mostly \(TourBuilder.describe(layer)) code."
        case .file:
            let types = graph.children(of: node.id).filter { $0.kind == .type }
            let refs = graph.fanIn(of: node.id)
            var text = "\(node.name) is a \(TourBuilder.describe(node.layer)) file with \(node.lineCount) lines"
            if !types.isEmpty { text += " declaring " + types.prefix(3).map(\.name).joined(separator: ", ") }
            if refs > 0 { text += "; \(refs) other file\(refs == 1 ? "" : "s") reference it" }
            if node.layer == .test || node.tags.contains("test") { text += ". Read the tests to see expected behaviour" }
            return text + "."
        case .type:
            if node.tags.contains("entry-point") {
                return "\(node.name) is the app's entry point, marked @main — everything starts here."
            }
            let fanIn = viewFanIn(node, in: graph)
            let kind = node.tags.contains("SwiftUI.View") ? "SwiftUI view" : (node.tags.contains("actor") ? "actor" : (node.tags.contains("protocol") ? "protocol" : "type"))
            var text = "\(node.name) is a \(kind)"
            if let file = graph.file(containing: node.id), file.id != node.id { text += " in \(file.name)" }
            if fanIn > 0 { text += ", referenced from \(fanIn) place\(fanIn == 1 ? "" : "s")" }
            if node.tags.contains("@State") { text += "; it keeps local @State" }
            if node.tags.contains("@Observable") { text += "; it is an @Observable model" }
            return text + "."
        case .extensionDecl:
            return "This extension adds behaviour to \(node.name)."
        case .function:
            return "\(node.name)() spans \(node.lineCount) lines" + (node.tags.contains("async") ? " and runs asynchronously." : ".")
        case .property:
            return "\(node.name) is a stored or computed property."
        }
    }

    static func describe(_ layer: ArchitectureLayer) -> String {
        switch layer {
        case .presentation: "presentation (UI)"
        case .domain: "domain"
        case .data: "data"
        case .infrastructure: "infrastructure"
        case .test: "test"
        case .unknown: "general"
        }
    }
}
