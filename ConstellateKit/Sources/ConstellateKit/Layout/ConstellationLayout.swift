import Foundation
import simd

/// Where one node lives in the 4-D constellation.
///
/// Axes (for the default radial styles; see `LayoutStyle.axes` for the others):
/// - x, z: angular sector (siblings share a parent's sector, children subdivide it) and shell radius (tree depth)
/// - y: architecture layer — a height band (`.shells`) or an elevation angle (`.celestial`) — with a deterministic jitter
/// - w: time. 0 = oldest modification in the project, 1 = newest. Projected to 3-D by `ConstellationLayout.position3`.
public struct LayoutPlacement: Hashable, Codable, Sendable {
    public var nodeID: NodeID
    public var position4: SIMD4<Float>
    /// Suggested visual radius in metres (cards scale with line count, clamped).
    public var radius: Float
    /// Tree depth / shell index (0 = root).
    public var shell: Int
    /// Angular sector in radians owned by this node's subtree (start ≤ end, may exceed 2π when wrapping).
    /// Non-sector styles (sphere, wall, spiral) store the node's azimuth in both fields.
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
    public var position3: SIMD3<Float> { SIMD3(position4.x, position4.y, position4.z) }
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
    /// Vertical band centres by layer. Presentation highest. (`.shells`, `.treeRadial`)
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

    // MARK: 3-D styles (celestial, sphere, wall, spiral)

    /// Eye height of a standing viewer; centre of the celestial shells, the sphere and the wall.
    public var eyeHeight: Float = 1.45
    /// No card centre goes lower than this (keeps immersive content above the real floor).
    public var floorClearance: Float = 0.35
    /// Elevation angle in degrees per layer for `.celestial`: UI high, infrastructure and tests low.
    public var layerElevations: [ArchitectureLayer: Float] = [
        .presentation: 34, .domain: 18, .unknown: 8, .data: 0, .infrastructure: -9, .test: -15
    ]
    /// Max deterministic elevation jitter (degrees) for `.celestial`.
    public var elevationJitter: Float = 4.5
    /// Free space kept between neighbouring cards on the sphere / wall / spiral (metres).
    public var cardGap: Float = 0.28
    /// Vertical / horizontal radius of the `.sphere` dome (1 = round; < 1 keeps tall spheres above the floor).
    public var sphereSquash: Float = 0.66
    /// Smallest sphere radius (the portfolio's `max(18, …)`, scaled to metres).
    public var minSphereRadius: Float = 2.4

    public init() {}

    enum CodingKeys: String, CodingKey {
        case baseRadius, shellSpacing, rootHeight, layerHeights, verticalJitter, sectorGap, timeDepth, minRadius, maxRadius
        case eyeHeight, floorClearance, layerElevations, elevationJitter, cardGap, sphereSquash, minSphereRadius
    }

    /// Tolerant decoding: missing keys keep their defaults, so configurations saved by older builds still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LayoutConfiguration()
        baseRadius = try c.decodeIfPresent(Float.self, forKey: .baseRadius) ?? d.baseRadius
        shellSpacing = try c.decodeIfPresent(Float.self, forKey: .shellSpacing) ?? d.shellSpacing
        rootHeight = try c.decodeIfPresent(Float.self, forKey: .rootHeight) ?? d.rootHeight
        layerHeights = try c.decodeIfPresent([ArchitectureLayer: Float].self, forKey: .layerHeights) ?? d.layerHeights
        verticalJitter = try c.decodeIfPresent(Float.self, forKey: .verticalJitter) ?? d.verticalJitter
        sectorGap = try c.decodeIfPresent(Float.self, forKey: .sectorGap) ?? d.sectorGap
        timeDepth = try c.decodeIfPresent(Float.self, forKey: .timeDepth) ?? d.timeDepth
        minRadius = try c.decodeIfPresent(Float.self, forKey: .minRadius) ?? d.minRadius
        maxRadius = try c.decodeIfPresent(Float.self, forKey: .maxRadius) ?? d.maxRadius
        eyeHeight = try c.decodeIfPresent(Float.self, forKey: .eyeHeight) ?? d.eyeHeight
        floorClearance = try c.decodeIfPresent(Float.self, forKey: .floorClearance) ?? d.floorClearance
        layerElevations = try c.decodeIfPresent([ArchitectureLayer: Float].self, forKey: .layerElevations) ?? d.layerElevations
        elevationJitter = try c.decodeIfPresent(Float.self, forKey: .elevationJitter) ?? d.elevationJitter
        cardGap = try c.decodeIfPresent(Float.self, forKey: .cardGap) ?? d.cardGap
        sphereSquash = try c.decodeIfPresent(Float.self, forKey: .sphereSquash) ?? d.sphereSquash
        minSphereRadius = try c.decodeIfPresent(Float.self, forKey: .minSphereRadius) ?? d.minSphereRadius
    }
}

/// Result of laying out a graph. Pure data; cheap to copy and to send across actors.
public struct ConstellationLayout: Codable, Sendable {
    public var placements: [NodeID: LayoutPlacement]
    public var configuration: LayoutConfiguration
    /// Axis-aligned 3-D bounds at dial = 0 (min, max).
    public var boundsMin: SIMD3<Float>
    public var boundsMax: SIMD3<Float>
    public var shellCount: Int
    /// Which strategy produced this layout.
    public var style: LayoutStyle
    /// Visual centre of the structure: origin of the time push and of edge bulges.
    public var center: SIMD3<Float>
    public var timeProjection: TimeProjection

    public init(placements: [NodeID: LayoutPlacement], configuration: LayoutConfiguration, boundsMin: SIMD3<Float>, boundsMax: SIMD3<Float>, shellCount: Int,
                style: LayoutStyle = .shells, center: SIMD3<Float> = .zero, timeProjection: TimeProjection = .cylindrical) {
        self.placements = placements
        self.configuration = configuration
        self.boundsMin = boundsMin
        self.boundsMax = boundsMax
        self.shellCount = shellCount
        self.style = style
        self.center = center
        self.timeProjection = timeProjection
    }

    enum CodingKeys: String, CodingKey { case placements, configuration, boundsMin, boundsMax, shellCount, style, center, timeProjection }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        placements = try c.decode([NodeID: LayoutPlacement].self, forKey: .placements)
        configuration = try c.decode(LayoutConfiguration.self, forKey: .configuration)
        boundsMin = try c.decode(SIMD3<Float>.self, forKey: .boundsMin)
        boundsMax = try c.decode(SIMD3<Float>.self, forKey: .boundsMax)
        shellCount = try c.decode(Int.self, forKey: .shellCount)
        style = try c.decodeIfPresent(LayoutStyle.self, forKey: .style) ?? .shells
        center = try c.decodeIfPresent(SIMD3<Float>.self, forKey: .center) ?? .zero
        timeProjection = try c.decodeIfPresent(TimeProjection.self, forKey: .timeProjection) ?? .cylindrical
    }

    public static let empty = ConstellationLayout(placements: [:], configuration: LayoutConfiguration(), boundsMin: .zero, boundsMax: .zero, shellCount: 0)

    public subscript(_ id: NodeID) -> LayoutPlacement? { placements[id] }

    /// Centre and radius of a sphere enclosing the bounds (for camera framing).
    public var boundingSphere: (center: SIMD3<Float>, radius: Float) {
        let c = (boundsMin + boundsMax) / 2
        return (c, max(0.5, simd_length(boundsMax - boundsMin) / 2))
    }

    /// Projects 4-D → 3-D.
    ///
    /// `timeDial` ∈ -1…1. At 0 the scene is the plain spatial layout. Positive values push *newer* code
    /// outward (away from `center`) and older code inward; negative values do the reverse. The mapping is
    /// continuous so the scene never snaps. Cylindrical styles push horizontally and lift 35 %; spherical
    /// styles push along the full 3-D direction from the centre.
    public func position3(for id: NodeID, timeDial: Float = 0) -> SIMD3<Float>? {
        guard let p = placements[id] else { return nil }
        return project(p, timeDial: timeDial)
    }

    /// Instance projection honouring this layout's `center` and `timeProjection`.
    public func project(_ p: LayoutPlacement, timeDial: Float) -> SIMD3<Float> {
        switch timeProjection {
        case .cylindrical:
            return ConstellationLayout.project(p, timeDial: timeDial, timeDepth: configuration.timeDepth, center: center)
        case .spherical:
            let base = p.position3
            guard timeDial != 0 else { return base }
            let dial = max(-1, min(1, timeDial))
            let t = p.position4.w - 0.5
            let radial = base - center
            let len = simd_length(radial)
            let dir = len > 0.0001 ? radial / len : SIMD3<Float>(0, 0, -1)
            return base + dir * (t * dial * configuration.timeDepth)
        }
    }

    /// The v1 cylindrical projection (FR-2.7), optionally around a vertical axis through `center`.
    public static func project(_ p: LayoutPlacement, timeDial: Float, timeDepth: Float, center: SIMD3<Float> = .zero) -> SIMD3<Float> {
        let base = SIMD3<Float>(p.position4.x, p.position4.y, p.position4.z)
        guard timeDial != 0 else { return base }
        let dial = max(-1, min(1, timeDial))
        // centred time: -0.5 (oldest) … +0.5 (newest)
        let t = p.position4.w - 0.5
        let radial = SIMD3<Float>(p.position4.x - center.x, 0, p.position4.z - center.z)
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

/// Builds a `ConstellationLayout` from a `CodeGraph` with the chosen `LayoutStyle`.
///
/// `.shells` (the default here, for API compatibility) is the original algorithm (Docs/PRD-Tech-Constellate.md §5.2):
/// 1. Weight every node by `max(1, lineCount)` summed over its subtree.
/// 2. Root owns the full circle. Each node splits its sector among children proportionally to weight,
///    leaving `sectorGap` between siblings; children are sorted by kind then name so the layout is stable.
/// 3. Radius = baseRadius + (depth − 1) × shellSpacing for depth ≥ 1; root at origin.
/// 4. y = layer band height + deterministic jitter (hash of id) × verticalJitter.
/// 5. w = normalised `modifiedAt` over the project (missing → inherited from parent → 0.5).
/// 6. Non-spatial nodes (functions, properties) inherit their file's placement (position identical, radius 0)
///    so edges can still be drawn to them.
///
/// `.celestial` runs the same sector recursion but maps (depth, sector, layer) to spherical coordinates around
/// the viewer's eye. The portfolio ports (`.sphere`, `.treeRadial`, `.wall`, `.spiral`) are documented on their
/// workers. All styles are deterministic: same graph, same sky.
public struct ConstellationLayoutEngine: Sendable {
    public var configuration: LayoutConfiguration
    public var style: LayoutStyle

    public init(configuration: LayoutConfiguration = LayoutConfiguration(), style: LayoutStyle = .shells) {
        self.configuration = configuration
        self.style = style
    }

    public func layout(_ graph: CodeGraph) -> ConstellationLayout {
        switch style {
        case .shells: RadialShellLayout(graph: graph, configuration: configuration, geometry: .disc).run()
        case .celestial: RadialShellLayout(graph: graph, configuration: configuration, geometry: .celestial).run()
        case .sphere: SphereLayout(context: LayoutContext(graph: graph, configuration: configuration)).run()
        case .treeRadial: TreeRadialLayout(context: LayoutContext(graph: graph, configuration: configuration)).run()
        case .wall: WallLayout(context: LayoutContext(graph: graph, configuration: configuration)).run()
        case .spiral: SpiralLayout(context: LayoutContext(graph: graph, configuration: configuration)).run()
        }
    }
}
