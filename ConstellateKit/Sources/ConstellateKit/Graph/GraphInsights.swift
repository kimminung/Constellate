import Foundation

/// File-level dependency analysis for the people reading the constellation: who depends on whom, what a change
/// would ripple into, which files are tangled in cycles, and Robert C. Martin's stability metrics.
///
/// Every relation edge whose `RelationKind.isDependency` is true is lifted to its files (a type → type `conforms`
/// edge becomes file → file). Self-edges (inside one file) and folder targets (imports) are ignored. Pure value;
/// build once per graph off the main actor.
public struct GraphInsights: Sendable {
    /// file → files it depends on (Ce, efferent).
    public let dependencies: [NodeID: Set<NodeID>]
    /// file → files that depend on it (Ca, afferent).
    public let dependents: [NodeID: Set<NodeID>]
    /// Strongly connected components with more than one file, largest first. Each is sorted by id.
    public let cycles: [[NodeID]]
    private let cycleIndex: [NodeID: Int]
    private let fileOf: [NodeID: NodeID]

    public init(graph: CodeGraph) {
        var fileOf: [NodeID: NodeID] = [:]
        for node in graph.nodes {
            if let file = graph.file(containing: node.id) { fileOf[node.id] = file.id }
        }
        var deps: [NodeID: Set<NodeID>] = [:]
        var rdeps: [NodeID: Set<NodeID>] = [:]
        for e in graph.edges where e.semantic?.isDependency == true {
            guard let a = fileOf[e.from], let b = fileOf[e.to], a != b else { continue }
            deps[a, default: []].insert(b)
            rdeps[b, default: []].insert(a)
        }
        let components = GraphInsights.stronglyConnectedComponents(nodes: graph.nodes(ofKind: .file).map(\.id), edges: deps)
        var cycles: [[NodeID]] = []
        for component in components where component.count > 1 {
            cycles.append(component.sorted { (a: NodeID, b: NodeID) -> Bool in a.raw < b.raw })
        }
        cycles.sort { (a: [NodeID], b: [NodeID]) -> Bool in
            if a.count != b.count { return a.count > b.count }
            return a[0].raw < b[0].raw
        }
        var index: [NodeID: Int] = [:]
        for (i, c) in cycles.enumerated() { for f in c { index[f] = i } }
        self.dependencies = deps
        self.dependents = rdeps
        self.cycles = cycles
        self.cycleIndex = index
        self.fileOf = fileOf
    }

    /// File that owns `id` (itself for files).
    public func file(of id: NodeID) -> NodeID? { fileOf[id] }

    /// Ca of the node's file — cheap (no traversal), for per-node encodings such as star size.
    public func fanIn(of id: NodeID) -> Int { fileOf[id].flatMap { dependents[$0]?.count } ?? 0 }

    /// Ce of the node's file — cheap (no traversal).
    public func fanOut(of id: NodeID) -> Int { fileOf[id].flatMap { dependencies[$0]?.count } ?? 0 }

    /// Every file in the cycle that contains `id`'s file (empty when it is not in one).
    public func cycleMembers(of id: NodeID) -> [NodeID] { cycle(containing: id).map { cycles[$0] } ?? [] }

    /// Index into `cycles` when the node's file is part of a dependency cycle.
    public func cycle(containing id: NodeID) -> Int? { fileOf[id].flatMap { cycleIndex[$0] } }

    /// True when the edge closes a loop: both ends' files sit in the same cycle.
    public func isCycleEdge(_ edge: CodeEdge) -> Bool {
        guard edge.semantic?.isDependency == true, let a = fileOf[edge.from], let b = fileOf[edge.to], a != b,
              let ca = cycleIndex[a], let cb = cycleIndex[b] else { return false }
        return ca == cb
    }

    /// Everything that (transitively) depends on `id` — "if I change this, what might break?" — with BFS depth.
    public func impact(of id: NodeID, maxDepth: Int = 3) -> [NodeID: Int] {
        bfs(from: id, along: dependents, maxDepth: maxDepth)
    }

    /// Everything `id` (transitively) depends on, with BFS depth.
    public func reach(of id: NodeID, maxDepth: Int = 3) -> [NodeID: Int] {
        bfs(from: id, along: dependencies, maxDepth: maxDepth)
    }

    public func metrics(for id: NodeID) -> NodeMetrics {
        guard let file = fileOf[id] else { return NodeMetrics(fanIn: 0, fanOut: 0, cycleIndex: nil, impact: 0) }
        return NodeMetrics(
            fanIn: dependents[file]?.count ?? 0,
            fanOut: dependencies[file]?.count ?? 0,
            cycleIndex: cycleIndex[file],
            impact: impact(of: file, maxDepth: .max).count
        )
    }

    private func bfs(from id: NodeID, along adjacency: [NodeID: Set<NodeID>], maxDepth: Int) -> [NodeID: Int] {
        guard let start = fileOf[id] else { return [:] }
        var seen: [NodeID: Int] = [:]
        var frontier: [NodeID] = [start]
        var depth = 0
        while !frontier.isEmpty && depth < maxDepth {
            depth += 1
            var next: [NodeID] = []
            for f in frontier {
                for g in adjacency[f, default: []].sorted(by: { $0.raw < $1.raw }) where g != start && seen[g] == nil {
                    seen[g] = depth
                    next.append(g)
                }
            }
            frontier = next
        }
        return seen
    }

    /// Iterative Tarjan (no recursion, so 4000-file graphs cannot overflow the stack).
    static func stronglyConnectedComponents(nodes: [NodeID], edges: [NodeID: Set<NodeID>]) -> [[NodeID]] {
        var index: [NodeID: Int] = [:]
        var low: [NodeID: Int] = [:]
        var onStack: Set<NodeID> = []
        var stack: [NodeID] = []
        var result: [[NodeID]] = []
        var counter = 0
        let sortedEdges = edges.mapValues { $0.sorted { $0.raw < $1.raw } }

        for root in nodes.sorted(by: { $0.raw < $1.raw }) where index[root] == nil {
            // (node, next child position)
            var work: [(NodeID, Int)] = [(root, 0)]
            while let top = work.last {
                let (v, i) = top
                if i == 0 {
                    index[v] = counter
                    low[v] = counter
                    counter += 1
                    stack.append(v)
                    onStack.insert(v)
                }
                let succ = sortedEdges[v] ?? []
                if i < succ.count {
                    work[work.count - 1].1 = i + 1
                    let w = succ[i]
                    if index[w] == nil {
                        work.append((w, 0))
                    } else if onStack.contains(w) {
                        low[v] = min(low[v]!, index[w]!)
                    }
                    continue
                }
                // All successors done.
                work.removeLast()
                if let parent = work.last?.0 {
                    low[parent] = min(low[parent]!, low[v]!)
                }
                if low[v] == index[v] {
                    var component: [NodeID] = []
                    while let w = stack.popLast() {
                        onStack.remove(w)
                        component.append(w)
                        if w == v { break }
                    }
                    result.append(component)
                }
            }
        }
        return result
    }
}

/// Coupling numbers for one node's file.
public struct NodeMetrics: Sendable, Hashable {
    /// Ca — files that depend on this file.
    public var fanIn: Int
    /// Ce — files this file depends on.
    public var fanOut: Int
    /// Index into `GraphInsights.cycles` when the file is in a dependency cycle.
    public var cycleIndex: Int?
    /// Files that transitively depend on this one (unbounded depth).
    public var impact: Int

    /// I = Ce / (Ca + Ce): 0 = maximally stable (everyone leans on it, it leans on nothing), 1 = maximally unstable.
    public var instability: Double? {
        let total = fanIn + fanOut
        return total == 0 ? nil : Double(fanOut) / Double(total)
    }
}
