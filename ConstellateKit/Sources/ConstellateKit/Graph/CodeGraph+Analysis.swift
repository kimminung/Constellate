import Foundation

/// Aggregate numbers about a graph, for dashboards and AI grounding.
public struct GraphStats: Codable, Sendable, Hashable {
    public var nodeCount: Int
    public var edgeCount: Int
    public var fileCount: Int
    public var totalLines: Int
    public var countsByKind: [NodeKind: Int]
    public var countsByLayer: [ArchitectureLayer: Int]
    public var countsByEdgeKind: [EdgeKind: Int]
    /// Oldest / newest `modifiedAt` among file nodes.
    public var oldestModified: Date?
    public var newestModified: Date?

    public init(
        nodeCount: Int,
        edgeCount: Int,
        fileCount: Int,
        totalLines: Int,
        countsByKind: [NodeKind: Int],
        countsByLayer: [ArchitectureLayer: Int],
        countsByEdgeKind: [EdgeKind: Int],
        oldestModified: Date?,
        newestModified: Date?
    ) {
        self.nodeCount = nodeCount
        self.edgeCount = edgeCount
        self.fileCount = fileCount
        self.totalLines = totalLines
        self.countsByKind = countsByKind
        self.countsByLayer = countsByLayer
        self.countsByEdgeKind = countsByEdgeKind
        self.oldestModified = oldestModified
        self.newestModified = newestModified
    }

    /// Convenience accessor returning 0 for absent kinds.
    public func count(of kind: NodeKind) -> Int { countsByKind[kind] ?? 0 }
    /// Convenience accessor returning 0 for absent layers (file nodes only).
    public func count(of layer: ArchitectureLayer) -> Int { countsByLayer[layer] ?? 0 }
    /// Convenience accessor returning 0 for absent edge kinds.
    public func count(of edge: EdgeKind) -> Int { countsByEdgeKind[edge] ?? 0 }
}

public extension CodeGraph {
    /// Nodes with the most incoming `references` edges (weighted), most referenced first.
    /// Only nodes with at least one incoming reference are returned.
    func hubs(limit: Int = 10) -> [CodeNode] {
        var scores: [NodeID: Float] = [:]
        for e in edges where e.kind == .references {
            scores[e.to, default: 0] += max(0.01, e.weight)
        }
        return scores
            .compactMap { id, score -> (CodeNode, Float)? in
                guard let n = node(id) else { return nil }
                return (n, score)
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0.name < b.0.name
            }
            .prefix(max(0, limit))
            .map(\.0)
    }

    /// Nodes tagged `entry-point` (the `@main` type and its file), types first.
    func entryPoints() -> [CodeNode] {
        nodes
            .filter { $0.tags.contains("entry-point") }
            .sorted { a, b in
                if a.kind.order != b.kind.order { return a.kind.order > b.kind.order }
                return a.name < b.name
            }
    }

    /// Number of incoming `references` edges to `id`.
    func fanIn(of id: NodeID) -> Int { incoming(to: id, kinds: [.references]).count }

    /// Counts per kind, layer and edge kind plus line totals and the modification date range.
    func stats() -> GraphStats {
        var byKind: [NodeKind: Int] = [:]
        var byLayer: [ArchitectureLayer: Int] = [:]
        var byEdge: [EdgeKind: Int] = [:]
        var oldest: Date?
        var newest: Date?
        var lines = 0
        var files = 0
        for n in nodes {
            byKind[n.kind, default: 0] += 1
            guard n.kind == .file else { continue }
            files += 1
            lines += n.lineCount
            byLayer[n.layer, default: 0] += 1
            if let d = n.modifiedAt {
                oldest = oldest.map { min($0, d) } ?? d
                newest = newest.map { max($0, d) } ?? d
            }
        }
        for e in edges { byEdge[e.kind, default: 0] += 1 }
        return GraphStats(
            nodeCount: nodes.count,
            edgeCount: edges.count,
            fileCount: files,
            totalLines: lines,
            countsByKind: byKind,
            countsByLayer: byLayer,
            countsByEdgeKind: byEdge,
            oldestModified: oldest,
            newestModified: newest
        )
    }

    /// Files sorted by line count (largest first), optionally restricted to layers.
    func busiestFiles(limit: Int = 5, layers: Set<ArchitectureLayer>? = nil) -> [CodeNode] {
        nodes(ofKind: .file)
            .filter { layers?.contains($0.layer) ?? true }
            .sorted { a, b in a.lineCount != b.lineCount ? a.lineCount > b.lineCount : a.name < b.name }
            .prefix(max(0, limit))
            .map { $0 }
    }

    /// Total lines of all files in the subtree rooted at `id`.
    func subtreeLines(of id: NodeID) -> Int {
        subtree(of: id).filter { $0.kind == .file }.reduce(0) { $0 + $1.lineCount }
    }
}
