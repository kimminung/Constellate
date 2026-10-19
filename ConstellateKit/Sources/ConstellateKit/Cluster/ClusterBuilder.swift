import Foundation

/// Groups graph nodes into `CodeCluster`s at a chosen granularity.
///
/// - `.folder`: one cluster per folder that directly contains at least one file (members = whole subtree).
/// - `.file`: one cluster per file (members = file + its symbols).
/// - `.type`: one cluster per type / extension (members = the declaration + its members);
///   files without any type become a file cluster so nothing is left out.
/// - `.feature`: one cluster per top-level folder under the root. When the root has a single child folder
///   (e.g. `Sources`) the split happens one level deeper. Files that sit directly at that level form a
///   cluster anchored at the level's folder.
///
/// Cluster ids are stable: `"cluster:<granularity>:<anchor node id>"`.
public struct ClusterBuilder: Sendable {
    public init() {}

    public func clusters(from graph: CodeGraph, granularity: ClusterGranularity) -> [CodeCluster] {
        switch granularity {
        case .folder: folderClusters(graph)
        case .file: fileClusters(graph)
        case .type: typeClusters(graph)
        case .feature: featureClusters(graph)
        }
    }

    /// Stable cluster identifier for an anchor node at a granularity.
    public static func clusterID(granularity: ClusterGranularity, anchor: NodeID) -> String {
        "cluster:\(granularity.rawValue):\(anchor.raw)"
    }

    // MARK: - Strategies

    private func folderClusters(_ graph: CodeGraph) -> [CodeCluster] {
        let containers = graph.nodes.filter { ($0.kind == .folder || $0.kind == .module) && graph.children(of: $0.id).contains { $0.kind == .file } }
        return containers
            .sorted { $0.path < $1.path }
            .map { folder in
                let members = graph.subtree(of: folder.id)
                return makeCluster(graph: graph, granularity: .folder, anchor: folder, title: folder.kind == .module ? folder.name : folder.name, members: members)
            }
    }

    private func fileClusters(_ graph: CodeGraph) -> [CodeCluster] {
        graph.nodes(ofKind: .file)
            .sorted { $0.path < $1.path }
            .map { file in
                makeCluster(graph: graph, granularity: .file, anchor: file, title: file.name, members: graph.subtree(of: file.id))
            }
    }

    private func typeClusters(_ graph: CodeGraph) -> [CodeCluster] {
        var out: [CodeCluster] = []
        for file in graph.nodes(ofKind: .file).sorted(by: { $0.path < $1.path }) {
            let declarations = graph.subtree(of: file.id).filter { $0.kind == .type || $0.kind == .extensionDecl }
            if declarations.isEmpty {
                out.append(makeCluster(graph: graph, granularity: .type, anchor: file, title: file.name, members: graph.subtree(of: file.id), fileOverride: file))
                continue
            }
            for decl in declarations {
                // Members = the declaration plus its non-type descendants (nested types get their own cluster).
                let members = [decl] + graph.subtree(of: decl.id).dropFirst().filter { $0.kind != .type && $0.kind != .extensionDecl }
                let title = decl.kind == .extensionDecl ? "extension \(decl.name)" : decl.name
                out.append(makeCluster(graph: graph, granularity: .type, anchor: decl, title: title, members: members, fileOverride: file))
            }
        }
        return out
    }

    private func featureClusters(_ graph: CodeGraph) -> [CodeCluster] {
        guard let root = graph.root else { return [] }
        var level = root
        // Descend through single-folder wrappers such as `Sources/`.
        for _ in 0..<3 {
            let kids = graph.children(of: level.id)
            let folders = kids.filter { $0.kind == .folder }
            let files = kids.filter { $0.kind == .file }
            if folders.count == 1 && files.isEmpty, let only = folders.first {
                level = only
            } else {
                break
            }
        }
        let kids = graph.children(of: level.id)
        var out: [CodeCluster] = []
        for folder in kids.filter({ $0.kind == .folder }).sorted(by: { $0.name < $1.name }) {
            out.append(makeCluster(graph: graph, granularity: .feature, anchor: folder, title: folder.name, members: graph.subtree(of: folder.id)))
        }
        let looseFiles = kids.filter { $0.kind == .file }
        if !looseFiles.isEmpty {
            let members = looseFiles.flatMap { graph.subtree(of: $0.id) }
            out.append(makeCluster(graph: graph, granularity: .feature, anchor: level, title: level.name, members: members))
        }
        if out.isEmpty {
            out.append(makeCluster(graph: graph, granularity: .feature, anchor: root, title: root.name, members: graph.subtree(of: root.id)))
        }
        return out
    }

    // MARK: - Assembly

    private func makeCluster(graph: CodeGraph, granularity: ClusterGranularity, anchor: CodeNode, title: String, members: [CodeNode], fileOverride: CodeNode? = nil) -> CodeCluster {
        let files = members.filter { $0.kind == .file }
        let totalLines: Int
        let dominant: ArchitectureLayer
        if files.isEmpty {
            // Type-level clusters: lines come from the declaration, layer from its file.
            totalLines = anchor.kind.isSpatial ? anchor.lineCount : 0
            dominant = fileOverride?.layer ?? anchor.layer
        } else {
            totalLines = files.reduce(0) { $0 + $1.lineCount }
            var counts: [ArchitectureLayer: Int] = [:]
            for f in files { counts[f.layer, default: 0] += 1 }
            dominant = counts.max { a, b in
                a.value != b.value ? a.value < b.value : a.key.rawValue > b.key.rawValue
            }?.key ?? anchor.layer
        }
        var cluster = CodeCluster(
            id: ClusterBuilder.clusterID(granularity: granularity, anchor: anchor.id),
            title: title,
            granularity: granularity,
            anchorNodeID: anchor.id,
            memberNodeIDs: members.map(\.id),
            totalLines: totalLines,
            dominantLayer: dominant
        )
        cluster.summary = ClusterBuilder.heuristicSummary(for: cluster, in: graph)
        return cluster
    }

    /// Heuristic one-line summary when the AI is unavailable, in the requested language (English by default so
    /// `CodeCluster.summary` and existing callers are unchanged).
    public static func heuristicSummary(for cluster: CodeCluster, in graph: CodeGraph, language: HostLanguage = .english) -> String {
        let members = cluster.memberNodeIDs.compactMap(graph.node)
        let files = members.filter { $0.kind == .file }.count
        let types = members.filter { $0.kind == .type }.count
        let funcs = members.filter { $0.kind == .function }.count
        let ko = language == .korean
        func count(_ n: Int, _ koUnit: String, _ enUnit: String) -> String {
            ko ? "\(koUnit) \(n)개" : "\(n) \(enUnit)\(n == 1 ? "" : "s")"
        }
        var parts: [String] = []
        if files > 0 { parts.append(count(files, "파일", "file")) }
        if types > 0 { parts.append(count(types, "타입", "type")) }
        if funcs > 0 { parts.append(count(funcs, "함수", "function")) }
        parts.append(ko ? "\(cluster.totalLines)줄" : "\(cluster.totalLines) lines")

        var notable: [String] = []
        let views = members.filter { $0.kind == .type && $0.tags.contains("SwiftUI.View") }.count
        if views > 0 { notable.append(count(views, "SwiftUI 뷰", "SwiftUI view")) }
        let observables = members.filter { $0.kind == .type && $0.tags.contains("@Observable") }.count
        if observables > 0 { notable.append(count(observables, "@Observable 모델", "@Observable model")) }
        let actors = members.filter { $0.kind == .type && $0.tags.contains("actor") }.count
        if actors > 0 { notable.append(count(actors, "액터", "actor")) }
        if members.contains(where: { $0.tags.contains("entry-point") }) { notable.append(language.pick("앱 진입점", "the app entry point")) }
        if members.contains(where: { $0.tags.contains("async") }) { notable.append(language.pick("비동기 코드", "async code")) }
        if members.contains(where: { $0.kind == .type && $0.tags.contains("protocol") }) { notable.append(language.pick("프로토콜", "protocols")) }
        let tests = members.filter { $0.kind == .file && ($0.layer == .test || $0.tags.contains("test")) }.count
        if tests > 0 { notable.append(count(tests, "테스트 파일", "test file")) }

        var text = "\(cluster.title): \(parts.joined(separator: ", ")) (\(cluster.dominantLayer.name(language)))."
        if !notable.isEmpty { text += language.pick(" 포함: ", " Includes ") + notable.joined(separator: ", ") + "." }
        return text
    }
}
