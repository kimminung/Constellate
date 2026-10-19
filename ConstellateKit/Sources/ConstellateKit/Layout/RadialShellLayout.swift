import Foundation
import simd

/// Worker for `.shells` and `.celestial`. See `ConstellationLayoutEngine` for the algorithm.
///
/// Hierarchical radial shells:
/// - every spatial node is weighted by the lines in its subtree,
/// - the root owns the whole circle and each node splits its sector among its spatial children
///   proportionally to weight (leaving `sectorGap` between siblings),
/// - radius grows with tree depth and `w` is the normalised modification time,
/// - `.disc` (the `.shells` style): height = architecture layer band + jitter — a flat disc ~2 m tall,
/// - `.celestial`: the same (depth, sector) pair becomes distance and azimuth around the viewer's eye, and the
///   architecture layer becomes an *elevation angle* — UI floats high, data at the horizon, tests low — so the
///   vertical separation between layers grows with depth instead of staying 2 m everywhere,
/// - non-spatial nodes (functions / properties) copy their nearest spatial ancestor with radius 0.
struct RadialShellLayout {
    enum Geometry { case disc, celestial }

    let graph: CodeGraph
    let configuration: LayoutConfiguration
    var geometry: Geometry = .disc

    /// Above this many spatial children the siblings are spread over sub-rings so cards don't overlap.
    private static let subRingThreshold = 48
    /// Above this many spatial children three sub-rings are used instead of two.
    private static let tripleRingThreshold = 120
    /// Radial offset of a sub-ring as a fraction of `shellSpacing`.
    private static let subRingOffset: Float = 0.3

    init(graph: CodeGraph, configuration: LayoutConfiguration, geometry: Geometry = .disc) {
        self.graph = graph
        self.configuration = configuration
        self.geometry = geometry
    }

    private var center: SIMD3<Float> {
        geometry == .celestial ? SIMD3(0, configuration.eyeHeight, 0) : .zero
    }

    func run() -> ConstellationLayout {
        let style: LayoutStyle = geometry == .celestial ? .celestial : .shells
        guard let root = graph.root else {
            return ConstellationLayout(placements: [:], configuration: configuration, boundsMin: .zero, boundsMax: .zero, shellCount: 0,
                                       style: style, center: center, timeProjection: style.timeProjection)
        }
        let context = LayoutContext(graph: graph, configuration: configuration)

        var placements: [NodeID: LayoutPlacement] = [:]
        placements.reserveCapacity(graph.nodes.count)

        // Root owns the full circle: at the origin (disc) or as the "pole star" above the viewer (celestial).
        let rootPosition: SIMD3<Float> = geometry == .celestial
            ? SIMD3(0, configuration.eyeHeight + configuration.baseRadius * 1.1, 0)
            : SIMD3(0, configuration.rootHeight, 0)
        placements[root.id] = context.placement(root, at: rootPosition, shell: 0, sectorStart: 0, sectorEnd: 2 * .pi)
        placeChildren(of: root.id, depth: 1, sectorStart: 0, sectorEnd: 2 * .pi, context: context, placements: &placements)

        // Spatial nodes unreachable from the root (broken parent links) still get a deterministic spot.
        return context.finish(&placements, style: style, center: center, projection: style.timeProjection) { node in
            let depth = max(1, graph.depth(of: node.id))
            let angle = LayoutContext.unitHash(node.id.raw) * 2 * .pi
            return position(radius: shellRadius(depth: depth), angle: angle, node: node, context: context)
        }
    }

    // MARK: Recursion

    private func placeChildren(of parentID: NodeID, depth: Int, sectorStart: Float, sectorEnd: Float,
                               context: LayoutContext, placements: inout [NodeID: LayoutPlacement]) {
        let children = context.spatialChildren(of: parentID)
        guard !children.isEmpty else { return }

        let span = max(0, sectorEnd - sectorStart)
        let n = children.count
        // Never let gaps eat more than a quarter of the sector.
        let gap = n > 1 ? min(configuration.sectorGap, span * 0.25 / Float(n - 1)) : 0
        let available = max(0, span - gap * Float(n - 1))
        let totalWeight = Float(children.reduce(0) { $0 + max(1, context.weights[$1.id] ?? 1) })

        let ringCount = n > RadialShellLayout.tripleRingThreshold ? 3 : (n > RadialShellLayout.subRingThreshold ? 2 : 1)
        let baseR = shellRadius(depth: depth)

        var cursor = sectorStart
        for (index, child) in children.enumerated() {
            let w = Float(max(1, context.weights[child.id] ?? 1))
            let angle = totalWeight > 0 ? available * (w / totalWeight) : available / Float(n)
            let start = cursor
            let end = max(start, start + angle)
            cursor = end + gap

            let mid = (start + end) / 2
            let r = baseR + subRingOffset(index: index, ringCount: ringCount)
            placements[child.id] = context.placement(child, at: position(radius: r, angle: mid, node: child, context: context),
                                                     shell: depth, sectorStart: start, sectorEnd: end)
            placeChildren(of: child.id, depth: depth + 1, sectorStart: start, sectorEnd: end, context: context, placements: &placements)
        }
    }

    /// (radius, azimuth) → 3-D for the chosen geometry.
    private func position(radius r: Float, angle: Float, node: CodeNode, context: LayoutContext) -> SIMD3<Float> {
        switch geometry {
        case .disc:
            return SIMD3(r * cos(angle), context.layerHeight(for: node), -r * sin(angle))
        case .celestial:
            var elevation = context.layerElevation(for: node)
            // Keep every card above the floor: raise the elevation just enough at large radii.
            let lowest = configuration.floorClearance - configuration.eyeHeight
            if r > 0.01, r * sin(elevation) < lowest {
                elevation = asin(max(-1, min(1, lowest / r)))
            }
            let horizontal = r * cos(elevation)
            return center + SIMD3(horizontal * cos(angle), r * sin(elevation), -horizontal * sin(angle))
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

    private func shellRadius(depth: Int) -> Float {
        depth <= 0 ? 0 : configuration.baseRadius + Float(depth - 1) * configuration.shellSpacing
    }

    // MARK: Deterministic hashing

    /// See `LayoutContext.unitHash` (kept here for existing callers and tests).
    static func unitHash(_ s: String) -> Float { LayoutContext.unitHash(s) }
}
