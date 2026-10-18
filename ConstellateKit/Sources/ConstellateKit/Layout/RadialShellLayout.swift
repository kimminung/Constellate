import Foundation
import simd

/// Internal worker for `ConstellationLayoutEngine`. See the engine's doc comment for the algorithm.
///
/// Hierarchical radial shells:
/// - every spatial node is weighted by the lines in its subtree,
/// - the root owns the whole circle and each node splits its sector among its spatial children
///   proportionally to weight (leaving `sectorGap` between siblings),
/// - radius grows with tree depth, height comes from the architecture layer plus a deterministic
///   jitter, and `w` is the normalised modification time,
/// - non-spatial nodes (functions / properties) copy their nearest spatial ancestor with radius 0.
struct RadialShellLayout {
    let graph: CodeGraph
    let configuration: LayoutConfiguration

    /// Above this many spatial children the siblings are spread over sub-rings so cards don't overlap.
    private static let subRingThreshold = 48
    /// Above this many spatial children three sub-rings are used instead of two.
    private static let tripleRingThreshold = 120
    /// Radial offset of a sub-ring as a fraction of `shellSpacing`.
    private static let subRingOffset: Float = 0.3

    func run() -> ConstellationLayout {
        guard let root = graph.root else {
            return ConstellationLayout(placements: [:], configuration: configuration, boundsMin: .zero, boundsMax: .zero, shellCount: 0)
        }

        let weights = subtreeWeights()
        let timeRange = modificationRange()

        var placements: [NodeID: LayoutPlacement] = [:]
        placements.reserveCapacity(graph.nodes.count)

        // Root at the origin, lifted to rootHeight, owning the full circle.
        let rootW = normalisedTime(for: root, range: timeRange) ?? 0.5
        placements[root.id] = LayoutPlacement(
            nodeID: root.id,
            position4: SIMD4(0, configuration.rootHeight, 0, rootW),
            radius: cardRadius(lineCount: weights[root.id] ?? 0),
            shell: 0,
            sectorStart: 0,
            sectorEnd: 2 * .pi
        )
        placeChildren(of: root.id, depth: 1, sectorStart: 0, sectorEnd: 2 * .pi, parentW: rootW, weights: weights, timeRange: timeRange, placements: &placements)

        // Spatial nodes unreachable from the root (broken parent links) still get a deterministic spot.
        for node in graph.nodes where node.kind.isSpatial && placements[node.id] == nil {
            let depth = max(1, graph.depth(of: node.id))
            let angle = RadialShellLayout.unitHash(node.id.raw) * 2 * .pi
            let r = shellRadius(depth: depth)
            let w = normalisedTime(for: node, range: timeRange) ?? 0.5
            placements[node.id] = LayoutPlacement(
                nodeID: node.id,
                position4: SIMD4(r * cos(angle), height(for: node), -r * sin(angle), w),
                radius: cardRadius(lineCount: weights[node.id] ?? node.lineCount),
                shell: depth,
                sectorStart: angle,
                sectorEnd: angle
            )
        }

        // Non-spatial nodes inherit the nearest spatial ancestor's position (radius 0).
        for node in graph.nodes where !node.kind.isSpatial {
            guard let anchor = nearestSpatialPlacement(for: node, in: placements) else { continue }
            var p = anchor
            p.nodeID = node.id
            p.radius = 0
            if let w = normalisedTime(for: node, range: timeRange) {
                p.position4.w = w
            }
            placements[node.id] = p
        }

        // Bounds over spatial nodes at dial 0.
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
        if minB.x > maxB.x {
            minB = .zero
            maxB = .zero
        }
        return ConstellationLayout(placements: placements, configuration: configuration, boundsMin: minB, boundsMax: maxB, shellCount: shellCount)
    }

    // MARK: Recursion

    private func placeChildren(
        of parentID: NodeID,
        depth: Int,
        sectorStart: Float,
        sectorEnd: Float,
        parentW: Float,
        weights: [NodeID: Int],
        timeRange: (min: TimeInterval, max: TimeInterval)?,
        placements: inout [NodeID: LayoutPlacement]
    ) {
        let children = graph.children(of: parentID)
            .filter { $0.kind.isSpatial }
            .sorted { lhs, rhs in
                if lhs.kind.order != rhs.kind.order { return lhs.kind.order < rhs.kind.order }
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.id.raw < rhs.id.raw
            }
        guard !children.isEmpty else { return }

        let span = max(0, sectorEnd - sectorStart)
        let n = children.count
        // Never let gaps eat more than a quarter of the sector.
        let gap = n > 1 ? min(configuration.sectorGap, span * 0.25 / Float(n - 1)) : 0
        let available = max(0, span - gap * Float(n - 1))
        let totalWeight = Float(children.reduce(0) { $0 + max(1, weights[$1.id] ?? 1) })

        let ringCount = n > RadialShellLayout.tripleRingThreshold ? 3 : (n > RadialShellLayout.subRingThreshold ? 2 : 1)
        let baseR = shellRadius(depth: depth)

        var cursor = sectorStart
        for (index, child) in children.enumerated() {
            let w = Float(max(1, weights[child.id] ?? 1))
            let angle = totalWeight > 0 ? available * (w / totalWeight) : available / Float(n)
            let start = cursor
            let end = max(start, start + angle)
            cursor = end + gap

            let mid = (start + end) / 2
            let r = baseR + subRingOffset(index: index, ringCount: ringCount)
            let nodeW = normalisedTime(for: child, range: timeRange) ?? parentW
            placements[child.id] = LayoutPlacement(
                nodeID: child.id,
                position4: SIMD4(r * cos(mid), height(for: child), -r * sin(mid), nodeW),
                radius: cardRadius(lineCount: weights[child.id] ?? child.lineCount),
                shell: depth,
                sectorStart: start,
                sectorEnd: end
            )
            placeChildren(of: child.id, depth: depth + 1, sectorStart: start, sectorEnd: end, parentW: nodeW, weights: weights, timeRange: timeRange, placements: &placements)
        }
    }

    private func subRingOffset(index: Int, ringCount: Int) -> Float {
        switch ringCount {
        case 2:
            return (index % 2 == 0 ? -1 : 1) * RadialShellLayout.subRingOffset * configuration.shellSpacing
        case 3:
            return Float(index % 3 - 1) * RadialShellLayout.subRingOffset * configuration.shellSpacing
        default:
            return 0
        }
    }

    // MARK: Helpers

    private func shellRadius(depth: Int) -> Float {
        depth <= 0 ? 0 : configuration.baseRadius + Float(depth - 1) * configuration.shellSpacing
    }

    private func height(for node: CodeNode) -> Float {
        let band = configuration.layerHeights[node.layer] ?? configuration.layerHeights[.unknown] ?? 1.3
        let jitter = (RadialShellLayout.unitHash(node.id.raw) * 2 - 1) * configuration.verticalJitter
        return band + jitter
    }

    private func cardRadius(lineCount: Int) -> Float {
        let raw = configuration.minRadius + Float(max(0, lineCount)).squareRoot() / 90
        return min(configuration.maxRadius, max(configuration.minRadius, raw))
    }

    private func nearestSpatialPlacement(for node: CodeNode, in placements: [NodeID: LayoutPlacement]) -> LayoutPlacement? {
        var cur = node.parent
        var guardCount = 0
        while let id = cur, guardCount < 64 {
            if let n = graph.node(id), n.kind.isSpatial, let p = placements[id] { return p }
            cur = graph.node(id)?.parent
            guardCount += 1
        }
        return nil
    }

    /// Subtree weight for every node: files count their own lines; folders/modules sum their children;
    /// types inside files use their own line range so they split the file's sector sensibly.
    private func subtreeWeights() -> [NodeID: Int] {
        var weights: [NodeID: Int] = [:]
        weights.reserveCapacity(graph.nodes.count)
        // Post-order over the tree so children are computed first.
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
            case .file:
                weights[n.id] = max(own, childSum)
            case .module, .folder:
                weights[n.id] = max(1, childSum)
            default:
                weights[n.id] = own
            }
        }
        // Nodes outside the tree
        for n in graph.nodes where weights[n.id] == nil {
            weights[n.id] = max(1, n.lineCount)
        }
        return weights
    }

    private func modificationRange() -> (min: TimeInterval, max: TimeInterval)? {
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

    private func normalisedTime(for node: CodeNode, range: (min: TimeInterval, max: TimeInterval)?) -> Float? {
        guard let range, let d = node.modifiedAt else { return nil }
        let span = range.max - range.min
        guard span > 0 else { return 0.5 }
        let t = (d.timeIntervalSinceReferenceDate - range.min) / span
        return Float(min(1, max(0, t)))
    }

    // MARK: Deterministic hashing

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
        // top 24 bits → exact float in [0, 1)
        return Float(z >> 40) / Float(1 << 24)
    }
}
