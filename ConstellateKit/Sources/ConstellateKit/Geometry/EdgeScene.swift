import Foundation
import simd

/// Which relations are drawn — the portfolio's `L` cycle (관계 끔 → 선택 → 전체).
public enum RelationDisplayMode: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    /// Tree lines only.
    case off
    /// Only relations touching the selected / hovered node, everything else stays quiet.
    case focus
    /// Every relation (plain references are dropped first on very large graphs).
    case all

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: "관계 끔 · Off"
        case .focus: "선택 · Focus"
        case .all: "전체 · All"
        }
    }

    public var symbol: String {
        switch self {
        case .off: "line.diagonal"
        case .focus: "scope"
        case .all: "point.3.connected.trianglepath.dotted"
        }
    }

    /// off → focus → all → off (the portfolio's order).
    public var next: RelationDisplayMode {
        switch self {
        case .off: .focus
        case .focus: .all
        case .all: .off
        }
    }
}

/// How loudly an edge is drawn.
public enum EdgeEmphasis: Int, Sendable, Hashable, Comparable, CaseIterable {
    /// Something else is focused; this edge recedes.
    case faint
    /// No focus.
    case normal
    /// Touches the focused node.
    case focus

    public static func < (a: EdgeEmphasis, b: EdgeEmphasis) -> Bool { a.rawValue < b.rawValue }
}

/// One merged mesh = one material. The app makes one entity per key.
public struct EdgeBatchKey: Hashable, Sendable, Comparable {
    /// `nil` = tree (`contains`) lines.
    public var relation: RelationKind?
    public var emphasis: EdgeEmphasis
    /// Part of a dependency cycle (`GraphInsights.isCycleEdge`) — drawn in the warning colour.
    public var isCycle: Bool

    public init(relation: RelationKind?, emphasis: EdgeEmphasis, isCycle: Bool = false) {
        self.relation = relation
        self.emphasis = emphasis
        self.isCycle = isCycle
    }

    /// Material opacity. Plain references and tree lines stay quiet so informative kinds read first.
    public var opacity: Float {
        guard let relation else { return emphasis == .faint ? 0.10 : 0.30 }
        let quiet = relation == .uses || relation == .imports
        switch emphasis {
        case .faint: return quiet ? 0.05 : 0.10
        case .normal: return isCycle ? 0.85 : (quiet ? 0.26 : 0.62)
        case .focus: return 0.95
        }
    }

    /// Warning colour for cycle edges (fixed; outside the code palette's reserved hues).
    public static let cycleColor = RGBA(hex: 0xFF5F6D)

    /// Tree lines take the theme's `edgeContains`; relations their `RelationStyle.color`; cycles the warning colour.
    public func color(theme: ConstellateTheme) -> RGBA {
        if isCycle { return EdgeBatchKey.cycleColor }
        guard let relation else { return theme.edgeContains.withAlpha(1) }
        return relation.style.color
    }

    /// Draw order: quiet first, so loud batches sort on top among transparents.
    public static func < (a: EdgeBatchKey, b: EdgeBatchKey) -> Bool {
        if a.emphasis != b.emphasis { return a.emphasis < b.emphasis }
        if a.isCycle != b.isCycle { return !a.isCycle }
        return (a.relation?.style.priority ?? -1) < (b.relation?.style.priority ?? -1)
    }
}

/// Triangle mesh in plain arrays (Foundation + simd only), turned into a `MeshResource` by the app.
/// `uvs.x` runs 0 → 1 along each edge in its *flow* direction, so a ramp texture shows direction without animation.
public struct TubeMesh: Sendable {
    public var positions: [SIMD3<Float>] = []
    public var normals: [SIMD3<Float>] = []
    public var uvs: [SIMD2<Float>] = []
    public var indices: [UInt32] = []

    public init() {}

    public var isEmpty: Bool { indices.isEmpty }
    public var triangleCount: Int { indices.count / 3 }

    /// A tube with `sides` faces around a polyline (parallel-transport frames, so it never twists).
    public mutating func appendTube(_ points: [SIMD3<Float>], radius: Float, sides: Int, uStart: Float, uEnd: Float) {
        guard points.count >= 2, sides >= 3, radius > 0 else { return }
        var cumulative: [Float] = [0]
        cumulative.reserveCapacity(points.count)
        for i in 1..<points.count { cumulative.append(cumulative[i - 1] + simd_length(points[i] - points[i - 1])) }
        let total = max(cumulative.last ?? 0, 1e-6)

        let base = UInt32(positions.count)
        var normal = TubeMesh.anyPerpendicular(to: TubeMesh.tangent(points, 0))
        for (i, p) in points.enumerated() {
            let t = TubeMesh.tangent(points, i)
            // Parallel transport: remove the tangent component from the previous normal.
            var n = normal - t * simd_dot(normal, t)
            if simd_length(n) < 1e-5 { n = TubeMesh.anyPerpendicular(to: t) }
            n = simd_normalize(n)
            normal = n
            let b = simd_cross(t, n)
            let u = uStart + (uEnd - uStart) * (cumulative[i] / total)
            for k in 0..<sides {
                let angle = Float(k) / Float(sides) * 2 * .pi
                let dir = n * cos(angle) + b * sin(angle)
                positions.append(p + dir * radius)
                normals.append(dir)
                uvs.append(SIMD2(u, Float(k) / Float(sides)))
            }
        }
        let s = UInt32(sides)
        for i in 0..<UInt32(points.count - 1) {
            for k in 0..<s {
                let a = base + i * s + k
                let b = base + i * s + (k + 1) % s
                let c = base + (i + 1) * s + (k + 1) % s
                let d = base + (i + 1) * s + k
                indices.append(contentsOf: [a, b, c, a, c, d])
            }
        }
    }

    /// Arrowhead: a cone whose tip is at `tip`, pointing along `direction`.
    public mutating func appendCone(tip: SIMD3<Float>, direction: SIMD3<Float>, length: Float, radius: Float, sides: Int = 8, u: Float = 1) {
        let len = simd_length(direction)
        guard len > 1e-6, length > 0, radius > 0 else { return }
        let d = direction / len
        let n = TubeMesh.anyPerpendicular(to: d)
        let b = simd_cross(d, n)
        let center = tip - d * length
        let base = UInt32(positions.count)
        for k in 0..<sides {
            let angle = Float(k) / Float(sides) * 2 * .pi
            let dir = n * cos(angle) + b * sin(angle)
            positions.append(center + dir * radius)
            normals.append(simd_normalize(dir * length + d * radius))
            uvs.append(SIMD2(u, Float(k) / Float(sides)))
        }
        positions.append(tip)
        normals.append(d)
        uvs.append(SIMD2(u, 0.5))
        positions.append(center)
        normals.append(-d)
        uvs.append(SIMD2(u, 0.5))
        let tipIndex = base + UInt32(sides), centerIndex = tipIndex + 1
        for k in 0..<UInt32(sides) {
            let a = base + k, c = base + (k + 1) % UInt32(sides)
            indices.append(contentsOf: [a, c, tipIndex])     // side
            indices.append(contentsOf: [c, a, centerIndex])  // base cap
        }
    }

    static func tangent(_ points: [SIMD3<Float>], _ i: Int) -> SIMD3<Float> {
        let a = points[max(0, i - 1)], b = points[min(points.count - 1, i + 1)]
        let d = b - a
        let len = simd_length(d)
        return len > 1e-6 ? d / len : SIMD3(0, 0, 1)
    }

    static func anyPerpendicular(to v: SIMD3<Float>) -> SIMD3<Float> {
        let helper: SIMD3<Float> = abs(v.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        return simd_normalize(simd_cross(v, helper))
    }
}

/// A polyline in *flow* direction along which particles travel (portfolio: `flowParticles`).
public struct FlowPath: Sendable {
    public var relation: RelationKind
    public var emphasis: EdgeEmphasis
    public var points: [SIMD3<Float>]
    /// Cumulative arc length per point (same count as `points`).
    public var lengths: [Float]
    public var particleCount: Int
    /// Metres per second.
    public var speed: Float

    public var totalLength: Float { lengths.last ?? 0 }

    public init(relation: RelationKind, emphasis: EdgeEmphasis, points: [SIMD3<Float>], particleCount: Int, speed: Float) {
        self.relation = relation
        self.emphasis = emphasis
        self.points = points
        var acc: [Float] = [0]
        for i in 1..<max(1, points.count) { acc.append(acc[i - 1] + simd_length(points[i] - points[i - 1])) }
        self.lengths = acc
        self.particleCount = particleCount
        self.speed = speed
    }

    /// Position at `fraction` (0…1, wrapped) of the arc length.
    public func point(atFraction fraction: Float) -> SIMD3<Float> {
        guard points.count > 1, totalLength > 0 else { return points.first ?? .zero }
        var f = fraction.truncatingRemainder(dividingBy: 1)
        if f < 0 { f += 1 }
        let target = f * totalLength
        // Binary search the segment.
        var lo = 0, hi = lengths.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if lengths[mid] < target { lo = mid } else { hi = mid }
        }
        let span = max(lengths[hi] - lengths[lo], 1e-6)
        let k = (target - lengths[lo]) / span
        return points[lo] + (points[hi] - points[lo]) * k
    }
}

/// What to draw.
public struct EdgeSceneOptions: Sendable {
    public var mode: RelationDisplayMode = .all
    /// Selected / hovered nodes. Edges touching them (or their contents) are emphasised; in `.focus` mode only those draw.
    public var focus: Set<NodeID> = []
    /// Relation kinds switched off in the legend.
    public var hidden: Set<RelationKind> = []
    public var showTree = true
    /// Viewer inside the structure (immersive): bulge arcs toward the centre so they come toward the viewer
    /// (portfolio: `inside ? -1 : 1`).
    public var bulgeInward = false
    public var timeDial: Float = 0
    public var edgeCap = 1500
    public var treeCap = 2500
    public var particleCap = 240
    /// Reduce Motion: a quarter of the particles.
    public var reduceMotion = false
    /// Dependency analysis for cycle highlighting (optional; pass `GraphInsights(graph:)`).
    public var insights: GraphInsights?
    /// Which cycle to draw in the warning colour. `nil` = the focused node's cycle, if it has one.
    /// Cycles are common inside one Swift module, so they are diagnosed on demand rather than painted everywhere.
    public var highlightedCycle: Int?

    public init() {}
}

/// Everything the renderer needs for one frame of relations: merged meshes per material, particle paths,
/// the set of nodes related to the focus (for dimming) and counts for the legend.
public struct EdgeScene: Sendable {
    public var batches: [EdgeBatchKey: TubeMesh] = [:]
    public var flows: [FlowPath] = []
    /// The expanded focus (the selection, its spatial contents and, for a member, its enclosing type / file) plus
    /// everything a drawn focus edge touches. Empty when nothing is focused (= nothing dims).
    public var related: Set<NodeID> = []
    /// Relation edges drawn, by kind.
    public var drawnCounts: [RelationKind: Int] = [:]
    /// All relation edges in the graph, by kind (legend numbers, like the portfolio's `edge-legend`).
    public var totalCounts: [RelationKind: Int] = [:]
    public var cycleEdgeCount = 0

    /// An empty scene (nothing drawn) — what the app shows before the first build and after `removeAll()`.
    public init() {}

    public var sortedBatchKeys: [EdgeBatchKey] { batches.keys.sorted() }
}

/// Builds `EdgeScene`s. Port of the portfolio's `rebuildEdges()` (quadratic Bézier arcs bulging away from the
/// centre, dashed type-system relations, arrowheads and flow particles on flow kinds, focus dimming), extended
/// with relation "lanes": each kind rotates its bulge around the chord by `RelationStyle.lane` and scales it by
/// `altitude`, so different relations between the same cards separate in 3-D instead of overlapping.
public enum EdgeSceneBuilder {
    static let dash: Float = 0.06
    static let gap: Float = 0.045

    public static func build(graph: CodeGraph, layout: ConstellationLayout, options: EdgeSceneOptions) -> EdgeScene {
        var scene = EdgeScene()
        let focus = expandFocus(options.focus, in: graph)
        let insights = options.insights
        let cycle: Int? = options.highlightedCycle ?? options.focus.lazy.compactMap { insights?.cycle(containing: $0) }.first
        func inHighlightedCycle(_ e: CodeEdge) -> Bool {
            guard let cycle, let insights, insights.isCycleEdge(e) else { return false }
            return insights.cycle(containing: e.from) == cycle
        }

        // 1. Pick edges.
        var relationEdges: [(edge: CodeEdge, relation: RelationKind, emphasis: EdgeEmphasis)] = []
        var treeEdges: [CodeEdge] = []
        for e in graph.edges {
            if e.kind == .contains {
                guard options.showTree, graph[e.from]?.kind.isSpatial == true, graph[e.to]?.kind.isSpatial == true else { continue }
                treeEdges.append(e)
                continue
            }
            guard let rel = e.semantic else { continue }
            scene.totalCounts[rel, default: 0] += 1
            guard !options.hidden.contains(rel) else { continue }
            // The highlighted cycle draws as a whole loop, even in focus mode, so the tangle can be read end to end.
            let touches = focus.contains(e.from) || focus.contains(e.to) || inHighlightedCycle(e)
            switch options.mode {
            case .off: continue
            case .focus: guard touches else { continue }
            case .all: break
            }
            let emphasis: EdgeEmphasis = touches ? .focus : (focus.isEmpty ? .normal : .faint)
            relationEdges.append((e, rel, emphasis))
        }
        // Portfolio rule: on big graphs plain references go first; then keep the most informative / heaviest.
        let unfocused = relationEdges.filter { $0.emphasis != .focus }
        if unfocused.count > 600 {
            relationEdges.removeAll { $0.emphasis != .focus && $0.relation == .uses }
        }
        if relationEdges.count > options.edgeCap {
            relationEdges.sort { a, b in
                if a.emphasis != b.emphasis { return a.emphasis > b.emphasis }
                if a.relation.style.priority != b.relation.style.priority { return a.relation.style.priority > b.relation.style.priority }
                if a.edge.weight != b.edge.weight { return a.edge.weight > b.edge.weight }
                return (a.edge.from.raw, a.edge.to.raw) < (b.edge.from.raw, b.edge.to.raw)
            }
            relationEdges = Array(relationEdges.prefix(options.edgeCap))
        }

        // 2. Tree lines: straight, thin, quiet.
        let treeEmphasis: EdgeEmphasis = focus.isEmpty ? .normal : .faint
        for e in treeEdges.prefix(options.treeCap) {
            guard let a = layout.position3(for: e.from, timeDial: options.timeDial),
                  let b = layout.position3(for: e.to, timeDial: options.timeDial), simd_distance(a, b) > 0.02 else { continue }
            let key = EdgeBatchKey(relation: nil, emphasis: treeEmphasis)
            scene.batches[key, default: TubeMesh()].appendTube([a, b], radius: treeEmphasis == .faint ? 0.0011 : 0.0016, sides: 3, uStart: 0.35, uEnd: 0.8)
        }

        // 3. Relation arcs.
        var flows: [FlowPath] = []
        for (e, rel, emphasis) in relationEdges {
            guard let a = layout.position3(for: e.from, timeDial: options.timeDial),
                  let b = layout.position3(for: e.to, timeDial: options.timeDial), simd_distance(a, b) > 0.02 else { continue }
            let isCycle = inHighlightedCycle(e)
            if isCycle { scene.cycleEdgeCount += 1 }
            let style = rel.style
            let points = arc(from: a, to: b, center: layout.center, style: style, inward: options.bulgeInward)
            // Flow direction: dependency direction, except kinds whose data flows back (binds).
            let flowPoints = rel.flowIsReversed ? Array(points.reversed()) : points
            let key = EdgeBatchKey(relation: rel, emphasis: emphasis, isCycle: isCycle)
            var mesh = scene.batches[key] ?? TubeMesh()
            let radius = tubeRadius(rel, emphasis: emphasis, weight: e.weight, cycle: isCycle)
            let sides = emphasis == .focus ? 5 : 3
            if style.dashed {
                for piece in dashes(flowPoints) {
                    mesh.appendTube(piece.points, radius: radius, sides: sides, uStart: piece.uStart, uEnd: piece.uEnd)
                }
            } else {
                mesh.appendTube(flowPoints, radius: radius, sides: sides, uStart: 0, uEnd: 1)
            }
            if style.flow || emphasis == .focus {
                appendArrow(to: &mesh, along: flowPoints, tubeRadius: radius)
            }
            scene.batches[key] = mesh
            scene.drawnCounts[rel, default: 0] += 1
            if emphasis == .focus {
                scene.related.insert(e.from)
                scene.related.insert(e.to)
            }
            if style.flow && emphasis != .faint {
                let n = min(3, 1 + max(1, Int(e.weight)))
                flows.append(FlowPath(relation: rel, emphasis: emphasis, points: flowPoints, particleCount: n, speed: emphasis == .focus ? 0.55 : 0.42))
            }
        }

        // 4. Particle budget: focus paths first, then by priority; Reduce Motion keeps a quarter.
        flows.sort { a, b in
            if a.emphasis != b.emphasis { return a.emphasis > b.emphasis }
            return a.relation.style.priority > b.relation.style.priority
        }
        let cap = options.reduceMotion ? max(1, options.particleCap / 4) : options.particleCap
        var used = 0
        for var f in flows {
            let room = cap - used
            guard room > 0 else { break }
            f.particleCount = min(options.reduceMotion ? 1 : f.particleCount, room)
            used += f.particleCount
            scene.flows.append(f)
        }

        // The selection's own contents never dim, even where they have no drawn relation of their own.
        if !focus.isEmpty { scene.related.formUnion(focus) }
        return scene
    }

    // MARK: Geometry

    /// Quadratic Bézier from `a` to `b` bulging away from (or toward) `center`, rotated into the kind's lane.
    public static func arc(from a: SIMD3<Float>, to b: SIMD3<Float>, center: SIMD3<Float>, style: RelationStyle, inward: Bool) -> [SIMD3<Float>] {
        let dist = simd_distance(a, b)
        let chord = (b - a) / max(dist, 1e-6)
        let mid = (a + b) / 2
        var out = mid - center
        if simd_length(out) < 1e-3 { out = SIMD3(0, 1, 0) }
        var n0 = out - chord * simd_dot(out, chord)
        if simd_length(n0) < 1e-4 {
            // Radial chords (inner shell → outer shell): bulge upward instead.
            let up = SIMD3<Float>(0, 1, 0)
            n0 = up - chord * simd_dot(up, chord)
            if simd_length(n0) < 1e-4 { n0 = TubeMesh.anyPerpendicular(to: chord) }
        }
        n0 = simd_normalize(n0)
        let n = n0 * cos(style.lane) + simd_cross(chord, n0) * sin(style.lane)
        // Portfolio: bulge = min(18, 0.25·dist + 2) panel units → metres.
        let height = min(1.4, 0.25 * dist + 0.16) * style.altitude * (inward ? -1 : 1)
        let control = mid + n * height
        let segments = max(10, min(32, Int(dist / 0.22) + 8))
        return (0...segments).map { i in
            let t = Float(i) / Float(segments)
            let s = 1 - t
            return a * (s * s) + control * (2 * s * t) + b * (t * t)
        }
    }

    static func tubeRadius(_ relation: RelationKind, emphasis: EdgeEmphasis, weight: Float, cycle: Bool) -> Float {
        let base: Float = relation == .uses || relation == .imports ? 0.0021 : 0.0031
        let emphasisScale: Float = switch emphasis {
        case .faint: 0.8
        case .normal: 1
        case .focus: 1.6
        }
        let weightScale = 1 + 0.25 * log2(max(1, weight))
        return base * emphasisScale * weightScale * (cycle ? 1.4 : 1)
    }

    /// Dash pieces along a polyline (constant metric dash/gap), each with its slice of the 0…1 flow coordinate.
    static func dashes(_ points: [SIMD3<Float>]) -> [(points: [SIMD3<Float>], uStart: Float, uEnd: Float)] {
        guard points.count >= 2 else { return [] }
        var cumulative: [Float] = [0]
        for i in 1..<points.count { cumulative.append(cumulative[i - 1] + simd_length(points[i] - points[i - 1])) }
        let total = cumulative.last ?? 0
        guard total > 0 else { return [] }
        func at(_ s: Float) -> SIMD3<Float> {
            var i = 1
            while i < cumulative.count - 1 && cumulative[i] < s { i += 1 }
            let span = max(cumulative[i] - cumulative[i - 1], 1e-6)
            let k = min(1, max(0, (s - cumulative[i - 1]) / span))
            return points[i - 1] + (points[i] - points[i - 1]) * k
        }
        var pieces: [(points: [SIMD3<Float>], uStart: Float, uEnd: Float)] = []
        var s0: Float = 0
        while s0 < total {
            let s1 = min(total, s0 + dash)
            var piece = [at(s0)]
            for (i, c) in cumulative.enumerated() where c > s0 && c < s1 { piece.append(points[i]) }
            piece.append(at(s1))
            if s1 - s0 > 0.004 { pieces.append((piece, s0 / total, s1 / total)) }
            s0 = s1 + gap
        }
        return pieces
    }

    static func appendArrow(to mesh: inout TubeMesh, along points: [SIMD3<Float>], tubeRadius: Float) {
        guard points.count >= 3 else { return }
        // Tip a little before the end so it is not buried inside the target card (portfolio: t = 0.96).
        let flow = FlowPath(relation: .uses, emphasis: .normal, points: points, particleCount: 0, speed: 0)
        let length = max(0.028, tubeRadius * 7)
        let total = flow.totalLength
        guard total > length * 2 else { return }
        let tipFraction = max(0.5, 1 - (0.06 + length * 0.2) / total)
        let tip = flow.point(atFraction: tipFraction)
        let back = flow.point(atFraction: tipFraction - length / total)
        mesh.appendCone(tip: tip, direction: tip - back, length: length, radius: max(0.0095, tubeRadius * 3.3), sides: 8, u: 1)
    }

    /// Focus ids plus their spatial descendants (a file's types) and, for members, the owning file and type.
    static func expandFocus(_ ids: Set<NodeID>, in graph: CodeGraph) -> Set<NodeID> {
        guard !ids.isEmpty else { return [] }
        var out = ids
        for id in ids {
            for n in graph.subtree(of: id) where n.kind.isSpatial { out.insert(n.id) }
            if let node = graph[id], !node.kind.isSpatial {
                for a in graph.ancestors(of: id) where a.kind.isSpatial { out.insert(a.id); if a.kind == .file { break } }
            }
        }
        return out
    }
}
