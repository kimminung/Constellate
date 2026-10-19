import Foundation

/// Stable identifier for a node in the code graph.
/// Built from the relative path plus a symbol path, e.g. `Sources/App/Foo.swift#Foo.bar(_:)`.
public struct NodeID: Hashable, Codable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public init(stringLiteral value: String) { self.raw = value }
    public var description: String { raw }
}

/// What a node represents. The order is the "tree depth" order used by layouts:
/// module → folder → file → type → member.
public enum NodeKind: String, Codable, Sendable, CaseIterable, Comparable {
    case module
    case folder
    case file
    case type          // struct / class / enum / actor / protocol
    case extensionDecl
    case function
    case property

    public static func < (lhs: NodeKind, rhs: NodeKind) -> Bool {
        lhs.order < rhs.order
    }

    public var order: Int {
        switch self {
        case .module: 0
        case .folder: 1
        case .file: 2
        case .type: 3
        case .extensionDecl: 3
        case .function: 4
        case .property: 4
        }
    }

    /// Nodes that are placed on their own in the constellation (members are drawn inside their file card).
    public var isSpatial: Bool { order <= 3 }
}

/// Coarse architecture layer, inferred from path and symbol names. Encoded as a colour band in the scene.
public enum ArchitectureLayer: String, Codable, Sendable, CaseIterable {
    case presentation   // Views, UI, Screens
    case domain         // Models, UseCases, Services
    case data           // Repositories, Network, Persistence
    case infrastructure // Utilities, Extensions, Config, Build
    case test
    case unknown
}

public struct LineRange: Hashable, Codable, Sendable {
    public var start: Int
    public var end: Int
    public init(start: Int, end: Int) {
        self.start = start
        self.end = max(start, end)
    }
    public var count: Int { end - start + 1 }
}

public struct CodeNode: Identifiable, Hashable, Codable, Sendable {
    public var id: NodeID
    public var name: String
    public var kind: NodeKind
    /// Path relative to the project root (folders end without slash). Modules use their name.
    public var path: String
    public var parent: NodeID?
    public var language: String?
    public var lines: LineRange?
    public var lineCount: Int
    public var modifiedAt: Date?
    public var layer: ArchitectureLayer
    /// Free-form tags from the extractor: "SwiftUI.View", "@Observable", "actor", "test", "entry-point" …
    public var tags: Set<String>
    /// What the file / type is for (App, View, Model, Service …), inferred by `RelationClassifier.inferRole`.
    /// `nil` for folders, the module and members. Optional so graphs encoded before roles existed still decode.
    public var role: CodeRole?

    public init(
        id: NodeID,
        name: String,
        kind: NodeKind,
        path: String,
        parent: NodeID? = nil,
        language: String? = nil,
        lines: LineRange? = nil,
        lineCount: Int = 0,
        modifiedAt: Date? = nil,
        layer: ArchitectureLayer = .unknown,
        tags: Set<String> = [],
        role: CodeRole? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.path = path
        self.parent = parent
        self.language = language
        self.lines = lines
        self.lineCount = lineCount
        self.modifiedAt = modifiedAt
        self.layer = layer
        self.tags = tags
        self.role = role
    }
}

public enum EdgeKind: String, Codable, Sendable, CaseIterable {
    case contains
    case imports
    case references
    case inherits
    case calls
}

public struct CodeEdge: Hashable, Codable, Sendable {
    public var from: NodeID
    public var to: NodeID
    public var kind: EdgeKind
    public var weight: Float
    /// What the edge means (composes / presents / binds / creates …). `nil` = not classified; use `semantic`,
    /// which falls back to `RelationKind.fallback(for: kind)`. Optional so older encodings still decode.
    public var relation: RelationKind?

    public init(from: NodeID, to: NodeID, kind: EdgeKind, weight: Float = 1, relation: RelationKind? = nil) {
        self.from = from
        self.to = to
        self.kind = kind
        self.weight = weight
        self.relation = relation
    }
}

/// The whole project as a tree (contains edges) plus a graph (every other edge kind).
/// Immutable value type; indices are rebuilt on init so lookups are O(1).
public struct CodeGraph: Codable, Sendable {
    public private(set) var nodes: [CodeNode]
    public private(set) var edges: [CodeEdge]
    public let rootID: NodeID
    public let projectName: String
    public let generatedAt: Date

    private var nodeIndex: [NodeID: Int] = [:]
    private var childrenIndex: [NodeID: [NodeID]] = [:]
    private var outgoingIndex: [NodeID: [CodeEdge]] = [:]
    private var incomingIndex: [NodeID: [CodeEdge]] = [:]

    enum CodingKeys: String, CodingKey { case nodes, edges, rootID, projectName, generatedAt }

    public init(projectName: String, rootID: NodeID, nodes: [CodeNode], edges: [CodeEdge], generatedAt: Date = .now) {
        self.projectName = projectName
        self.rootID = rootID
        self.nodes = nodes
        self.edges = edges
        self.generatedAt = generatedAt
        rebuildIndices()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.nodes = try c.decode([CodeNode].self, forKey: .nodes)
        self.edges = try c.decode([CodeEdge].self, forKey: .edges)
        self.rootID = try c.decode(NodeID.self, forKey: .rootID)
        self.projectName = try c.decode(String.self, forKey: .projectName)
        self.generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        rebuildIndices()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(nodes, forKey: .nodes)
        try c.encode(edges, forKey: .edges)
        try c.encode(rootID, forKey: .rootID)
        try c.encode(projectName, forKey: .projectName)
        try c.encode(generatedAt, forKey: .generatedAt)
    }

    private mutating func rebuildIndices() {
        nodeIndex = [:]
        childrenIndex = [:]
        outgoingIndex = [:]
        incomingIndex = [:]
        for (i, n) in nodes.enumerated() {
            nodeIndex[n.id] = i
            if let p = n.parent { childrenIndex[p, default: []].append(n.id) }
        }
        for e in edges where e.kind != .contains {
            outgoingIndex[e.from, default: []].append(e)
            incomingIndex[e.to, default: []].append(e)
        }
    }

    // MARK: Lookups

    public var root: CodeNode? { node(rootID) }

    public func node(_ id: NodeID) -> CodeNode? {
        guard let i = nodeIndex[id] else { return nil }
        return nodes[i]
    }

    public subscript(_ id: NodeID) -> CodeNode? { node(id) }

    public func children(of id: NodeID) -> [CodeNode] {
        (childrenIndex[id] ?? []).compactMap(node)
    }

    public func childIDs(of id: NodeID) -> [NodeID] { childrenIndex[id] ?? [] }

    public func parent(of id: NodeID) -> CodeNode? {
        guard let p = node(id)?.parent else { return nil }
        return node(p)
    }

    /// Ancestors from the immediate parent up to the root.
    public func ancestors(of id: NodeID) -> [CodeNode] {
        var out: [CodeNode] = []
        var cur = node(id)?.parent
        while let c = cur, let n = node(c) {
            out.append(n)
            cur = n.parent
        }
        return out
    }

    public func depth(of id: NodeID) -> Int { ancestors(of: id).count }

    /// Pre-order traversal of the subtree rooted at `id` (including `id`).
    public func subtree(of id: NodeID) -> [CodeNode] {
        guard let start = node(id) else { return [] }
        var out: [CodeNode] = []
        var stack: [CodeNode] = [start]
        while let n = stack.popLast() {
            out.append(n)
            stack.append(contentsOf: children(of: n.id).reversed())
        }
        return out
    }

    public func outgoing(from id: NodeID, kinds: Set<EdgeKind>? = nil) -> [CodeEdge] {
        let all = outgoingIndex[id] ?? []
        guard let kinds else { return all }
        return all.filter { kinds.contains($0.kind) }
    }

    public func incoming(to id: NodeID, kinds: Set<EdgeKind>? = nil) -> [CodeEdge] {
        let all = incomingIndex[id] ?? []
        guard let kinds else { return all }
        return all.filter { kinds.contains($0.kind) }
    }

    /// Non-tree edges, i.e. the "graph" part.
    public var relationEdges: [CodeEdge] { edges.filter { $0.kind != .contains } }

    public func nodes(ofKind kind: NodeKind) -> [CodeNode] { nodes.filter { $0.kind == kind } }

    /// File node that contains a symbol node (or the node itself if it is a file).
    public func file(containing id: NodeID) -> CodeNode? {
        var cur = node(id)
        while let n = cur {
            if n.kind == .file { return n }
            cur = n.parent.flatMap(node)
        }
        return nil
    }

    public var fileCount: Int { nodes.lazy.filter { $0.kind == .file }.count }
    public var totalLines: Int { nodes.lazy.filter { $0.kind == .file }.reduce(0) { $0 + $1.lineCount } }
}
