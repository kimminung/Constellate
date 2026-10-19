import Foundation
import simd
import Testing
@testable import ConstellateKit

/// Contract tests for every `LayoutStyle` (the registry contract in `LayoutStyle.swift`), plus the specific
/// promises of the 3-D styles: celestial elevation by layer, the sphere's dome, the wall's constant distance,
/// the spiral's reading order.
@Suite struct LayoutStyleTests {
    let graph = SampleGraph.orbitNotes()

    private func layout(_ style: LayoutStyle) -> ConstellationLayout {
        ConstellationLayoutEngine(style: style).layout(graph)
    }

    @Test(arguments: LayoutStyle.allCases)
    func everyNodeIsPlacedAndMetadataMatches(style: LayoutStyle) throws {
        let l = layout(style)
        for node in graph.nodes { #expect(l[node.id] != nil, "\(style): \(node.id) not placed") }
        #expect(l.style == style)
        #expect(l.timeProjection == style.timeProjection)
        #expect(l.boundsMax.x > l.boundsMin.x && l.boundsMax.y > l.boundsMin.y && l.boundsMax.z > l.boundsMin.z)
        for (_, p) in l.placements {
            #expect(p.position4.w >= 0 && p.position4.w <= 1)
            #expect(p.position3.x.isFinite && p.position3.y.isFinite && p.position3.z.isFinite)
        }
    }

    @Test(arguments: LayoutStyle.allCases)
    func layoutsAreDeterministic(style: LayoutStyle) {
        #expect(layout(style).placements == layout(style).placements)
    }

    @Test(arguments: [LayoutStyle.celestial, .sphere, .wall, .spiral, .treeRadial])
    func cardsStayAboveTheFloor(style: LayoutStyle) {
        let l = layout(style)
        for node in graph.nodes where node.kind.isSpatial {
            let y = l[node.id]?.position3.y ?? -1
            #expect(y >= l.configuration.floorClearance - 0.12, "\(style): \(node.name) at y \(y)")
        }
    }

    /// Portfolio layouts promise panels that never touch (`radius from count and panel size`).
    @Test(arguments: [LayoutStyle.sphere, .wall, .spiral, .treeRadial])
    func surfaceCardsDoNotCollide(style: LayoutStyle) {
        let l = layout(style)
        let spatial = graph.nodes.filter { $0.kind.isSpatial }.compactMap { l[$0.id] }
        var worst: Float = .greatestFiniteMagnitude
        for (i, a) in spatial.enumerated() {
            for b in spatial[(i + 1)...] {
                worst = min(worst, simd_distance(a.position3, b.position3) - (a.radius + b.radius) * 0.8)
            }
        }
        #expect(worst > 0, "\(style): closest pair overlaps by \(-worst) m")
    }

    @Test func celestialIsGenuinelyThreeDimensional() throws {
        let celestial = layout(.celestial), shells = layout(.shells)
        let tallC = celestial.boundsMax.y - celestial.boundsMin.y
        let tallS = shells.boundsMax.y - shells.boundsMin.y
        #expect(tallC > tallS * 1.6, "celestial \(tallC) m vs shells \(tallS) m")
        // Layer → elevation: presentation cards sit higher (as an angle from the eye) than data, data than tests.
        let eye = SIMD3<Float>(0, celestial.configuration.eyeHeight, 0)
        func meanElevation(_ layer: ArchitectureLayer) -> Float {
            let files = graph.nodes(ofKind: .file).filter { $0.layer == layer }
            let angles = files.compactMap { celestial[$0.id] }.map { p -> Float in
                let d = p.position3 - eye
                return atan2(d.y, simd_length(SIMD2(d.x, d.z)))
            }
            return angles.reduce(0, +) / Float(max(1, angles.count))
        }
        #expect(meanElevation(.presentation) > meanElevation(.domain))
        #expect(meanElevation(.domain) > meanElevation(.data))
        #expect(meanElevation(.data) > meanElevation(.test))
        // Depth → distance from the eye, as in the shells.
        for node in graph.nodes where node.kind.isSpatial && node.id != graph.rootID {
            let parent = try #require(node.parent)
            guard graph[parent]?.kind != .module else { continue }
            let p = try #require(celestial[node.id]), pp = try #require(celestial[parent])
            #expect(simd_distance(p.position3, eye) > simd_distance(pp.position3, eye) + 0.3, "\(node.name)")
        }
        // The root is the pole star above the viewer.
        let root = try #require(celestial[graph.rootID])
        #expect(root.position3.y > eye.y + 1 && abs(root.position3.x) < 1e-4 && abs(root.position3.z) < 1e-4)
    }

    @Test func celestialKeepsTheShellSectors() throws {
        let celestial = layout(.celestial), shells = layout(.shells)
        for node in graph.nodes where node.kind.isSpatial {
            let a = try #require(celestial[node.id]), b = try #require(shells[node.id])
            #expect(a.sectorStart == b.sectorStart && a.sectorEnd == b.sectorEnd && a.shell == b.shell)
            #expect(a.radius == b.radius && a.position4.w == b.position4.w)
        }
    }

    @Test func sphereIsADomeWithFolderHubsOutside() throws {
        let l = layout(.sphere)
        let c = l.center
        let squash = l.configuration.sphereSquash
        var radii: [Float] = []
        for node in graph.nodes where node.kind == .file || node.kind == .type {
            let p = try #require(l[node.id]).position3 - c
            radii.append(simd_length(SIMD3(p.x, p.y / squash, p.z)))
        }
        let r0 = radii[0]
        #expect(radii.allSatisfy { abs($0 - r0) < 1e-3 }, "surface cards share one (squashed) radius")
        #expect(r0 >= l.configuration.minSphereRadius - 1e-3)
        for folder in graph.nodes(ofKind: .folder) {
            let p = try #require(l[folder.id]).position3 - c
            #expect(simd_length(SIMD3(p.x, p.y / squash, p.z)) > r0, "\(folder.name) hub floats outside")
        }
        // Patch ordering: a file's types are its spatial neighbours, not 137° away.
        let file = try #require(graph["OrbitNotes/App/AppRouter.swift"])
        let type = try #require(graph.children(of: file.id).first { $0.kind == .type })
        #expect(simd_distance(try #require(l[file.id]).position3, try #require(l[type.id]).position3) < r0 * 0.9)
    }

    @Test func patchOrderIsANeighbourWalk() {
        let pts = SphereLayout.patchOrderedFibonacci(count: 400)
        #expect(pts.count == 400)
        let mean = zip(pts, pts.dropFirst()).map { simd_distance($0, $1) }.reduce(0, +) / 399
        // Golden-angle order averages ~1.3 between consecutive points; the serpentine walk stays local.
        #expect(mean < 0.35, "mean step \(mean)")
        #expect(pts.allSatisfy { abs(simd_length($0) - 1) < 1e-4 })
    }

    @Test func wallKeepsEveryCardAtOneDistance() throws {
        let l = layout(.wall)
        let surface = graph.nodes.filter { $0.kind.isSpatial && $0.kind != .module }
        let d = surface.compactMap { l[$0.id] }.map { simd_length(SIMD2($0.position3.x, $0.position3.z)) }
        #expect(d.max()! - d.min()! < 1e-3, "one cylinder")
        #expect(d[0] >= 3 - 1e-3)
        // Reading order: a folder header comes before (left of / above) its first file.
        let folder = try #require(graph["OrbitNotes/Features/Notes/Views"])
        let first = try #require(graph.children(of: folder.id).first { $0.kind == .file })
        let pf = try #require(l[folder.id]).position3, p1 = try #require(l[first.id]).position3
        #expect(pf.y > p1.y + 1e-3 || pf.x < p1.x)
    }

    @Test func spiralClimbsInReadingOrder() throws {
        let l = layout(.spiral)
        let order = graph.nodes.isEmpty ? [] : LayoutContext(graph: graph, configuration: l.configuration).preorderSpatial().filter { $0.kind != .module }
        let ys = order.compactMap { l[$0.id]?.position3.y }
        #expect(ys.count == order.count)
        #expect(zip(ys, ys.dropFirst()).allSatisfy { $0 < $1 }, "each stop is higher than the previous one")
        #expect((ys.last ?? 0) - (ys.first ?? 0) < 8, "bounded height for a standing viewer")
    }

    @Test func treeRadialRingsGrowWithDepth() throws {
        let l = layout(.treeRadial)
        var byDepth: [Int: [Float]] = [:]
        for file in graph.nodes(ofKind: .file) {
            let p = try #require(l[file.id]).position3
            byDepth[graph.depth(of: file.id), default: []].append(simd_length(SIMD2(p.x, p.z)))
        }
        let depths = byDepth.keys.sorted()
        for (a, b) in zip(depths, depths.dropFirst()) {
            #expect((byDepth[a]!.max() ?? 0) < (byDepth[b]!.min() ?? 0) + 1e-3, "ring \(a) inside ring \(b)")
        }
        // Types stand just behind their file.
        let file = try #require(graph["OrbitNotes/App/AppRouter.swift"])
        let pf = try #require(l[file.id]).position3
        for type in graph.children(of: file.id) where type.kind == .type {
            let pt = try #require(l[type.id]).position3
            #expect(simd_length(SIMD2(pt.x, pt.z)) > simd_length(SIMD2(pf.x, pf.z)))
        }
    }

    @Test func sphericalTimeProjectionIsContinuousAndRadial() throws {
        let l = layout(.celestial)
        let id: NodeID = "OrbitNotes/Data/Network/SyncClient.swift"
        let p = try #require(l[id])
        let at0 = try #require(l.position3(for: id, timeDial: 0))
        #expect(at0 == p.position3)
        let half = try #require(l.position3(for: id, timeDial: 0.5)), full = try #require(l.position3(for: id, timeDial: 1))
        #expect(abs(simd_length(full - at0) - 2 * simd_length(half - at0)) < 1e-4)
        // Displacement is parallel to the direction from the centre.
        let dir = simd_normalize(at0 - l.center)
        let move = full - at0
        if simd_length(move) > 1e-5 {
            #expect(abs(abs(simd_dot(simd_normalize(move), dir)) - 1) < 1e-3)
        }
    }

    @Test func emptyGraphsYieldEmptyLayouts() {
        let g = CodeGraph(projectName: "E", rootID: "missing", nodes: [], edges: [])
        for style in LayoutStyle.allCases {
            #expect(ConstellationLayoutEngine(style: style).layout(g).placements.isEmpty)
        }
    }

    @Test func configurationDecodesOlderPayloads() throws {
        let legacy = #"{"baseRadius":2,"shellSpacing":1,"rootHeight":1.5,"layerHeights":[],"verticalJitter":0.3,"sectorGap":0.04,"timeDepth":1.2,"minRadius":0.08,"maxRadius":0.32}"#
        let c = try JSONDecoder().decode(LayoutConfiguration.self, from: Data(legacy.utf8))
        #expect(c.baseRadius == 2 && c.eyeHeight == LayoutConfiguration().eyeHeight)
        let layout = layout(.sphere)
        let decoded = try JSONDecoder().decode(ConstellationLayout.self, from: JSONEncoder().encode(layout))
        #expect(decoded.style == .sphere && decoded.center == layout.center && decoded.placements == layout.placements)
    }
}
