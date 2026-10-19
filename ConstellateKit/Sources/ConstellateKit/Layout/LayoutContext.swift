import Foundation
import simd

/// Everything the layout strategies share: subtree weights, the time axis, card sizing, layer heights,
/// deterministic hashing and the final "members inherit / bounds" pass. One instance per `layout(_:)` call.
///
/// Keeping this in one place means every `LayoutStyle` encodes the same facts the same way
/// (card size = lines, w = recency, colour = layer) and differs only in *where* it puts things.
struct LayoutContext {
    let graph: CodeGraph
    let configuration: LayoutConfiguration
    /// Subtree line weight per node (files: own lines or their types' sum; folders: sum of children).
    let weights: [NodeID: Int]
    private let timeRange: (min: TimeInterval, max: TimeInterval)?

    init(graph: CodeGraph, configuration: LayoutConfiguration) {
        self.graph = graph
        self.configuration = configuration
        self.weights = LayoutContext.subtreeWeights(graph)
        self.timeRange = LayoutContext.modificationRange(graph)
    }

    // MARK: Tree

    /// Spatial children in the stable layout order: kind, then name, then id.
    func spatialChildren(of id: NodeID) -> [CodeNode] {
        graph.children(of: id)
            .filter { $0.kind.isSpatial }
            .sorted { lhs, rhs in
                if lhs.kind.order != rhs.kind.order { return lhs.kind.order < rhs.kind.order }
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.id.raw < rhs.id.raw
            }
    }

    /// Pre-order walk of spatial nodes from the root ("path order": a folder, then its files, each file
    /// followed by its types). The portfolio layouts index panels in this order so siblings stay together.
    func preorderSpatial() -> [CodeNode] {
        guard let root = graph.root else { return [] }
        var out: [CodeNode] = []
        var stack: [CodeNode] = [root]
        var visited: Set<NodeID> = []
        while let n = stack.popLast() {
            guard visited.insert(n.id).inserted else { continue }
            out.append(n)
            stack.append(contentsOf: spatialChildren(of: n.id).reversed())
        }
        return out
    }

    /// Cards that sit on the surface of the sphere / wall / spiral layouts: files, types and extensions.
    /// Folders and the module become hubs placed relative to them.
    func surfaceItems() -> [CodeNode] {
        preorderSpatial().filter { $0.kind != .module && $0.kind != .folder }
    }

    // MARK: Encoding shared by every style

    func cardRadius(for node: CodeNode) -> Float {
        cardRadius(lineCount: weights[node.id] ?? node.lineCount)
    }

    func cardRadius(lineCount: Int) -> Float {
        let raw = configuration.minRadius + Float(max(0, lineCount)).squareRoot() / 90
        return min(configuration.maxRadius, max(configuration.minRadius, raw))
    }

    /// Layer band height plus a deterministic jitter (the classic "y = architecture layer" rule).
    func layerHeight(for node: CodeNode) -> Float {
        let band = configuration.layerHeights[node.layer] ?? configuration.layerHeights[.unknown] ?? 1.3
        let jitter = (LayoutContext.unitHash(node.id.raw) * 2 - 1) * configuration.verticalJitter
        return band + jitter
    }

    /// Layer elevation angle (radians) plus a deterministic jitter, for the spherical styles.
    func layerElevation(for node: CodeNode) -> Float {
        let degrees = configuration.layerElevations[node.layer] ?? configuration.layerElevations[.unknown] ?? 8
        let jitter = (LayoutContext.unitHash(node.id.raw + "#elev") * 2 - 1) * configuration.elevationJitter
        return (degrees + jitter) * .pi / 180
    }

    func normalisedTime(for node: CodeNode) -> Float? {
        guard let range = timeRange, let d = node.modifiedAt else { return nil }
        let span = range.max - range.min
        guard span > 0 else { return 0.5 }
        let t = (d.timeIntervalSinceReferenceDate - range.min) / span
        return Float(min(1, max(0, t)))
    }

    /// `w` for a node: its own time, else its nearest dated ancestor's, else 0.5.
    func time(for node: CodeNode) -> Float {
        if let t = normalisedTime(for: node) { return t }
        for a in graph.ancestors(of: node.id) {
            if let t = normalisedTime(for: a) { return t }
        }
        return 0.5
    }

    func placement(_ node: CodeNode, at p: SIMD3<Float>, shell: Int, sectorStart: Float, sectorEnd: Float) -> LayoutPlacement {
        LayoutPlacement(
            nodeID: node.id,
            position4: SIMD4(p.x, p.y, p.z, time(for: node)),
            radius: cardRadius(for: node),
            shell: shell,
            sectorStart: sectorStart,
            sectorEnd: sectorEnd
        )
    }

    /// Azimuth of a point around the vertical axis through `center`, in the shells' convention
    /// (x = r·cos θ, z = −r·sin θ), mapped to 0…2π.
    static func azimuth(of p: SIMD3<Float>, around center: SIMD3<Float> = .zero) -> Float {
        var a = atan2(-(p.z - center.z), p.x - center.x)
        if a < 0 { a += 2 * .pi }
        return a
    }

    // MARK: Finishing

    /// Members (functions / properties) copy their nearest spatial ancestor (radius 0), spatial nodes that the
    /// strategy did not reach get a deterministic fallback, then bounds and shell count are computed.
    func finish(_ placements: inout [NodeID: LayoutPlacement], style: LayoutStyle, center: SIMD3<Float>, projection: TimeProjection,
                fallback: (CodeNode) -> SIMD3<Float>) -> ConstellationLayout {
        for node in graph.nodes where node.kind.isSpatial && placements[node.id] == nil {
            let p = fallback(node)
            let a = LayoutContext.azimuth(of: p, around: center)
            placements[node.id] = placement(node, at: p, shell: max(1, graph.depth(of: node.id)), sectorStart: a, sectorEnd: a)
        }
        for node in graph.nodes where !node.kind.isSpatial {
            guard let anchor = nearestSpatialPlacement(for: node, in: placements) else { continue }
            var p = anchor
            p.nodeID = node.id
            p.radius = 0
            if let w = normalisedTime(for: node) { p.position4.w = w }
            placements[node.id] = p
        }
        let (minB, maxB, shellCount) = bounds(of: placements)
        return ConstellationLayout(placements: placements, configuration: configuration, boundsMin: minB, boundsMax: maxB,
                                   shellCount: shellCount, style: style, center: center, timeProjection: projection)
    }

    func nearestSpatialPlacement(for node: CodeNode, in placements: [NodeID: LayoutPlacement]) -> LayoutPlacement? {
        var cur = node.parent
        var guardCount = 0
        while let id = cur, guardCount < 64 {
            if let n = graph.node(id), n.kind.isSpatial, let p = placements[id] { return p }
            cur = graph.node(id)?.parent
            guardCount += 1
        }
        return nil
    }

    /// Bounds over spatial nodes at dial 0 (cards included), plus `shellCount` = max shell + 1.
    func bounds(of placements: [NodeID: LayoutPlacement]) -> (SIMD3<Float>, SIMD3<Float>, Int) {
        var minB = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxB = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var shellCount = 0
        for (id, p) in placements {
            guard let node = graph.node(id), node.kind.isSpatial else { continue }
            let pos = SIMD3(p.position4.x, p.position4.y, p.position4.z)
            minB = simd_min(minB, pos - SIMD3(repeating: p.radius))
            maxB = simd_max(maxB, pos + SIMD3(repeating: p.radius))
            shellCount = max(shellCount, p.shell + 1)
        }
        if minB.x > maxB.x { return (.zero, .zero, 0) }
        return (minB, maxB, shellCount)
    }

    // MARK: Precomputation

    /// Subtree weight for every node: files count their own lines; folders/modules sum their children;
    /// types inside files use their own line range so they split the file's sector sensibly.
    static func subtreeWeights(_ graph: CodeGraph) -> [NodeID: Int] {
        var weights: [NodeID: Int] = [:]
        weights.reserveCapacity(graph.nodes.count)
        guard let root = graph.root else { return weights }
        var order: [CodeNode] = []
        var stack: [CodeNode] = [root]
        var visited: Set<NodeID> = []
        while let n = stack.popLast() {
            guard visited.insert(n.id).inserted else { continue }
            order.append(n)
            stack.append(contentsOf: graph.children(of: n.id))
        }
        for n in order.reversed() {
            let own = max(1, n.lineCount)
            let childSum = graph.children(of: n.id).filter { $0.kind.isSpatial }.reduce(0) { $0 + (weights[$1.id] ?? 0) }
            switch n.kind {
            case .file: weights[n.id] = max(own, childSum)
            case .module, .folder: weights[n.id] = max(1, childSum)
            default: weights[n.id] = own
            }
        }
        for n in graph.nodes where weights[n.id] == nil {
            weights[n.id] = max(1, n.lineCount)
        }
        return weights
    }

    static func modificationRange(_ graph: CodeGraph) -> (min: TimeInterval, max: TimeInterval)? {
        var lo = TimeInterval.greatestFiniteMagnitude
        var hi = -TimeInterval.greatestFiniteMagnitude
        var any = false
        for n in graph.nodes {
            guard let d = n.modifiedAt else { continue }
            any = true
            lo = min(lo, d.timeIntervalSinceReferenceDate)
            hi = max(hi, d.timeIntervalSinceReferenceDate)
        }
        return any ? (lo, hi) : nil
    }

    /// FNV-1a 64 followed by a SplitMix64 finaliser, mapped to 0…1. Stable across processes
    /// (Swift's `Hasher` is randomly seeded, so it cannot be used for layout).
    static func unitHash(_ s: String) -> Float {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        var z = h &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Float(z >> 40) / Float(1 << 24)
    }
}
