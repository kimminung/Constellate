import Foundation
import simd

/// Where one node lives in the 4-D constellation.
///
/// Axes:
/// - x, z: angular sector (siblings share a parent's sector, children subdivide it) and shell radius (tree depth)
/// - y: architecture layer band (presentation high, infrastructure low) with a deterministic jitter
/// - w: time. 0 = oldest modification in the project, 1 = newest. Projected to 3-D by `ConstellationLayout.position3`.
public struct LayoutPlacement: Hashable, Codable, Sendable {
    public var nodeID: NodeID
    public var position4: SIMD4<Float>
    /// Suggested visual radius in metres (cards scale with line count, clamped).
    public var radius: Float
    /// Tree depth / shell index (0 = root).
    public var shell: Int
    /// Angular sector in radians owned by this node's subtree (start ≤ end, may exceed 2π when wrapping).
    public var sectorStart: Float
    public var sectorEnd: Float

    public init(nodeID: NodeID, position4: SIMD4<Float>, radius: Float, shell: Int, sectorStart: Float, sectorEnd: Float) {
        self.nodeID = nodeID
        self.position4 = position4
        self.radius = radius
        self.shell = shell
        self.sectorStart = sectorStart
        self.sectorEnd = sectorEnd
    }

    public var sectorMid: Float { (sectorStart + sectorEnd) / 2 }
}

/// Tunables for the layout engine. Defaults are sized for a person standing at the origin of an
/// immersive space (shells start 1.6 m away, the farthest shell around 6–8 m).
public struct LayoutConfiguration: Hashable, Codable, Sendable {
    /// Radius of shell 1 (root's children). Root sits at the origin, lifted to `rootHeight`.
    public var baseRadius: Float = 1.6
    /// Distance between consecutive shells.
    public var shellSpacing: Float = 1.25
    /// Height of the root node.
    public var rootHeight: Float = 1.5
    /// Vertical band centres by layer. Presentation highest.
    public var layerHeights: [ArchitectureLayer: Float] = [
        .presentation: 2.1, .domain: 1.6, .data: 1.15, .infrastructure: 0.75, .test: 0.5, .unknown: 1.3
    ]
    /// Max deterministic vertical jitter so siblings don't overlap.
    public var verticalJitter: Float = 0.35
    /// Gap (radians) left between sibling sectors so subtrees stay visually separated.
    public var sectorGap: Float = 0.04
    /// How much a unit of w (time) displaces a node along its radial direction when the time dial is fully on.
    public var timeDepth: Float = 1.2
    /// Card radius bounds in metres.
    public var minRadius: Float = 0.08
    public var maxRadius: Float = 0.32

    public init() {}
}

/// Result of laying out a graph. Pure data; cheap to copy and to send across actors.
public struct ConstellationLayout: Codable, Sendable {
    public var placements: [NodeID: LayoutPlacement]
    public var configuration: LayoutConfiguration
    /// Axis-aligned 3-D bounds at dial = 0 (min, max).
    public var boundsMin: SIMD3<Float>
    public var boundsMax: SIMD3<Float>
    public var shellCount: Int

    public init(placements: [NodeID: LayoutPlacement], configuration: LayoutConfiguration, boundsMin: SIMD3<Float>, boundsMax: SIMD3<Float>, shellCount: Int) {
        self.placements = placements
        self.configuration = configuration
        self.boundsMin = boundsMin
        self.boundsMax = boundsMax
        self.shellCount = shellCount
    }

    public static let empty = ConstellationLayout(placements: [:], configuration: LayoutConfiguration(), boundsMin: .zero, boundsMax: .zero, shellCount: 0)

    public subscript(_ id: NodeID) -> LayoutPlacement? { placements[id] }

    /// Projects 4-D → 3-D.
    ///
    /// `timeDial` ∈ -1…1. At 0 the scene is the plain spatial layout. Positive values push *newer* code
    /// outward and lift it slightly (so "what changed recently" bulges towards the viewer's horizon);
    /// negative values do the reverse. The mapping is continuous so the scene never snaps.
    public func position3(for id: NodeID, timeDial: Float = 0) -> SIMD3<Float>? {
        guard let p = placements[id] else { return nil }
        return ConstellationLayout.project(p, timeDial: timeDial, timeDepth: configuration.timeDepth)
    }

    public static func project(_ p: LayoutPlacement, timeDial: Float, timeDepth: Float) -> SIMD3<Float> {
        let base = SIMD3<Float>(p.position4.x, p.position4.y, p.position4.z)
        guard timeDial != 0 else { return base }
        let dial = max(-1, min(1, timeDial))
        // centred time: -0.5 (oldest) … +0.5 (newest)
        let t = p.position4.w - 0.5
        let radial = SIMD3<Float>(p.position4.x, 0, p.position4.z)
        let len = simd_length(radial)
        let dir = len > 0.0001 ? radial / len : SIMD3<Float>(0, 0, -1)
        let push = dir * (t * dial * timeDepth)
        let lift = SIMD3<Float>(0, t * dial * timeDepth * 0.35, 0)
        return base + push + lift
    }

    /// Centroid (dial 0) of a set of nodes; used to place cluster orbs.
    public func centroid(of ids: some Sequence<NodeID>, timeDial: Float = 0) -> SIMD3<Float>? {
        var sum = SIMD3<Float>.zero
        var n: Float = 0
        for id in ids {
            if let p = position3(for: id, timeDial: timeDial) {
                sum += p
                n += 1
            }
        }
        return n > 0 ? sum / n : nil
    }
}

/// Builds a `ConstellationLayout` from a `CodeGraph`.
///
/// Algorithm (hierarchical radial shells, see Docs/PRD-Tech-Constellate.md §5.2):
/// 1. Weight every node by `max(1, lineCount)` summed over its subtree.
/// 2. Root owns the full circle. Each node splits its sector among children proportionally to weight,
///    leaving `sectorGap` between siblings; children are sorted by kind then name so the layout is stable.
/// 3. Radius = baseRadius + (depth − 1) × shellSpacing for depth ≥ 1; root at origin.
/// 4. y = layer band height + deterministic jitter (hash of id) × verticalJitter.
/// 5. w = normalised `modifiedAt` over the project (missing → inherited from parent → 0.5).
/// 6. Non-spatial nodes (functions, properties) inherit their file's placement (position identical, radius 0)
///    so edges can still be drawn to them.
public struct ConstellationLayoutEngine: Sendable {
    public var configuration: LayoutConfiguration

    public init(configuration: LayoutConfiguration = LayoutConfiguration()) {
        self.configuration = configuration
    }

    public func layout(_ graph: CodeGraph) -> ConstellationLayout {
        RadialShellLayout(graph: graph, configuration: configuration).run()
    }
}
