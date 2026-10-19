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
/// Every feature keeps working; only the prose gets plainer. Speaks the app's `HostLanguage` (Korean first).
nonisolated enum HeuristicHost {

    static func locate(_ query: String, in graph: CodeGraph, limit: Int = 6, language: HostLanguage) -> HostReply {
        let hits = CodeSearcher().search(query, in: graph, limit: limit)
        guard !hits.isEmpty else {
            return HostReply(language.pick(
                "\"\(query)\"에 맞는 코드를 찾지 못했어요. 타입 이름이나 폴더, 또는 @State 같은 태그로 다시 말해 주세요.",
                "I couldn't find anything matching \"\(query)\". Try a type name, a folder, or a tag like @State."))
        }
        var lines = [language.pick(
            "\"\(query)\" 검색 결과 \(hits.count)건:",
            "Found \(hits.count) match\(hits.count == 1 ? "" : "es") for \"\(query)\":")]
        for hit in hits {
            guard let node = graph.node(hit.nodeID) else { continue }
            lines.append("• \(node.name) (\(node.kind.name(language)), \(node.layer.name(language))) — \(hit.reason)")
        }
        return HostReply(lines.joined(separator: "\n"), nodeIDs: hits.map(\.nodeID))
    }

    static func explain(_ id: NodeID, in graph: CodeGraph, language: HostLanguage) -> HostReply {
        guard let node = graph.node(id) else {
            return HostReply(language.pick("그 노드는 더 이상 그래프에 없습니다.", "That node is no longer in the graph."))
        }
        var parts: [String] = []
        let out = graph.outgoing(from: id)
        let inc = graph.incoming(to: id)
        let children = graph.children(of: id)
        let outNames = out.prefix(5).compactMap { graph.node($0.to)?.name }.joined(separator: ", ")
        let childNames = children.prefix(6).map(\.name).joined(separator: ", ")
        let extraChildren = max(0, children.count - 6)
        switch language {
        case .korean:
            parts.append("\(node.name): \(node.layer.name(language)) 레이어의 \(describe(node.kind, language)), 경로 \(node.path)")
            if let lines = node.lines { parts.append("\(lines.start)–\(lines.end)행") } else if node.lineCount > 0 { parts.append("\(node.lineCount)줄") }
            if !node.tags.isEmpty { parts.append("태그: " + node.tags.sorted().joined(separator: ", ")) }
            if !out.isEmpty { parts.append("\(verb(out, language)): \(outNames)") }
            if !inc.isEmpty { parts.append("다른 노드 \(inc.count)개가 의존") }
            if !children.isEmpty { parts.append("포함: " + childNames + (extraChildren > 0 ? " 외 \(extraChildren)개" : "")) }
        case .english:
            parts.append("\(node.name) is a \(describe(node.kind, language)) in the \(node.layer.name(language)) layer, at \(node.path)")
            if let lines = node.lines { parts.append("lines \(lines.start)–\(lines.end)") } else if node.lineCount > 0 { parts.append("\(node.lineCount) lines") }
            if !node.tags.isEmpty { parts.append("tags: " + node.tags.sorted().joined(separator: ", ")) }
            if !out.isEmpty { parts.append("it \(verb(out, language)) \(outNames)") }
            if !inc.isEmpty { parts.append("\(inc.count) other node\(inc.count == 1 ? "" : "s") depend on it") }
            if !children.isEmpty { parts.append("contains " + childNames + (extraChildren > 0 ? " and \(extraChildren) more" : "")) }
        }
        let related = out.map(\.to) + inc.map(\.from)
        return HostReply(parts.joined(separator: "; ") + ".", nodeIDs: [id] + Array(related.prefix(5)))
    }

    static func summarize(_ cluster: CodeCluster, in graph: CodeGraph, language: HostLanguage) -> HostReply {
        var text = ClusterBuilder.heuristicSummary(for: cluster, in: graph, language: language)
        let members = cluster.memberNodeIDs.compactMap(graph.node)
        let views = members.filter { $0.tags.contains("SwiftUI.View") }.count
        if views > 0 { text += language.pick(" SwiftUI 뷰 \(views)개.", " \(views) SwiftUI view\(views == 1 ? "" : "s").") }
        let imports = Set(members.flatMap { graph.outgoing(from: $0.id, kinds: [.imports]).compactMap { graph.node($0.to)?.name } })
        if !imports.isEmpty {
            let list = imports.sorted().prefix(5).joined(separator: ", ")
            text += language.pick(" import: \(list).", " Imports \(list).")
        }
        return HostReply(text, nodeIDs: Array(cluster.memberNodeIDs.prefix(6)))
    }

    static func review(_ id: NodeID, source: String, in graph: CodeGraph, language: HostLanguage) -> HostReply {
        guard let node = graph.node(id) else { return HostReply(language.pick("리뷰할 대상이 없습니다.", "Nothing to review.")) }
        var notes: [String] = []
        let lineCount = source.split(whereSeparator: \.isNewline).count
        let kind = describe(node.kind, language)
        if lineCount > 300 {
            notes.append(language.pick("\(lineCount)줄이나 되는 큰 \(kind)입니다. 분리를 고려하세요.",
                                       "At \(lineCount) lines this \(kind) is large; consider splitting it."))
        }
        if source.contains("!") && source.contains("try!") {
            notes.append(language.pick("`try!`가 있습니다 — `do/catch`나 `try?`를 쓰세요.", "`try!` found — prefer `do/catch` or `try?`."))
        }
        if source.contains("as!") {
            notes.append(language.pick("강제 캐스팅 `as!`가 있습니다 — `as?`로 안전하게 처리하세요.", "Forced cast `as!` found — guard with `as?`."))
        }
        if source.contains("DispatchQueue") {
            notes.append(language.pick("GCD를 사용합니다 — 구조적 동시성(async/await)을 고려하세요.", "GCD usage — consider structured concurrency."))
        }
        if source.contains("@State") && source.contains("class ") {
            notes.append(language.pick("클래스 타입 프로퍼티에 `@State`가 붙어 있습니다 — 모델이 `@Observable`인지 확인하세요.",
                                       "`@State` on a class-typed property — make sure the model is `@Observable`."))
        }
        let incoming = graph.incoming(to: id).count
        if incoming > 12 {
            notes.append(language.pick("의존하는 노드가 \(incoming)개입니다 — 변경 영향이 넓으니 테스트를 추가하세요.",
                                       "\(incoming) dependents — changes here ripple widely; add tests."))
        }
        if notes.isEmpty {
            notes.append(language.pick("\(node.name)의 구조만 훑어봤을 때 뚜렷한 문제는 없습니다. 로직은 직접 확인해 주세요.",
                                       "No obvious issues from a structural pass over \(node.name). Review the logic by hand."))
        }
        return HostReply(notes.joined(separator: " "), nodeIDs: [id])
    }

    static func tour(for graph: CodeGraph, language: HostLanguage) -> LearningTour {
        TourBuilder().tour(for: graph, language: language)
    }

    /// Catch-all chat answer: tries a search first, then describes the project.
    static func chat(_ text: String, graph: CodeGraph, clusters: [CodeCluster], docked: CodeCluster?, language: HostLanguage) -> HostReply {
        if let docked {
            let s = summarize(docked, in: graph, language: language)
            return HostReply(language.pick("\(docked.title) 안에서: ", "From inside \(docked.title): ") + s.text, nodeIDs: s.nodeIDs)
        }
        let hits = CodeSearcher().search(text, in: graph, limit: 4)
        if !hits.isEmpty { return locate(text, in: graph, limit: 4, language: language) }
        return HostReply(language.pick(
            "\(graph.projectName)에는 파일 \(graph.fileCount)개, \(graph.totalLines)줄이 클러스터 \(clusters.count)개에 나뉘어 있습니다. 찾기, 설명, 리뷰, 투어를 요청해 보세요.",
            "\(graph.projectName) has \(graph.fileCount) files and \(graph.totalLines) lines in \(clusters.count) clusters. Ask me to find, explain, review or tour something."))
    }

    // MARK: - helpers

    static func describe(_ kind: NodeKind, _ language: HostLanguage) -> String {
        switch kind {
        case .file: language.pick("소스 파일", "source file")
        default: kind.name(language)
        }
    }

    private static func verb(_ edges: [CodeEdge], _ language: HostLanguage) -> String {
        let kinds = Set(edges.map(\.kind))
        if kinds == [.imports] { return language.pick("import", "imports") }
        if kinds == [.inherits] { return language.pick("상속·채택", "inherits from / conforms to") }
        if kinds == [.calls] { return language.pick("호출", "calls") }
        return language.pick("참조", "references")
    }
}
