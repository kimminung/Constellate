import Foundation
import simd
import Testing
@testable import ConstellateKit

@Suite struct LayoutTests {
    let graph = SampleGraph.orbitNotes()
    let engine = ConstellationLayoutEngine()

    @Test func everySpatialNodeIsPlacedAndRootAtOrigin() throws {
        let layout = engine.layout(graph)
        for node in graph.nodes {
            #expect(layout[node.id] != nil, "\(node.id) not placed")
        }
        let root = try #require(layout[graph.rootID])
        #expect(root.position4.x == 0)
        #expect(root.position4.z == 0)
        #expect(root.position4.y == layout.configuration.rootHeight)
        #expect(root.shell == 0)
        #expect(root.sectorStart == 0)
        #expect(abs(root.sectorEnd - 2 * .pi) < 1e-5)
        #expect(layout.shellCount >= 4)
        #expect(layout.boundsMax.x > layout.boundsMin.x)
        #expect(layout.boundsMax.z > layout.boundsMin.z)
    }

    @Test func childrenLieOnOuterShells() throws {
        let layout = engine.layout(graph)
        func planarRadius(_ p: LayoutPlacement) -> Float { simd_length(SIMD2(p.position4.x, p.position4.z)) }
        for node in graph.nodes where node.kind.isSpatial && node.id != graph.rootID {
            let parent = try #require(node.parent)
            let p = try #require(layout[node.id])
            let pp = try #require(layout[parent])
            #expect(p.shell == pp.shell + 1)
            #expect(planarRadius(p) > planarRadius(pp) + 0.1, "\(node.id) radius \(planarRadius(p)) vs parent \(planarRadius(pp))")
            #expect(p.sectorEnd >= p.sectorStart)
            // child sector within parent sector
            #expect(p.sectorStart >= pp.sectorStart - 1e-4)
            #expect(p.sectorEnd <= pp.sectorEnd + 1e-4)
            #expect(p.radius >= layout.configuration.minRadius && p.radius <= layout.configuration.maxRadius)
        }
    }

    @Test func siblingSectorsDoNotOverlap() throws {
        let layout = engine.layout(graph)
        for parent in graph.nodes where parent.kind.isSpatial {
            let kids = graph.children(of: parent.id).filter { $0.kind.isSpatial }.compactMap { layout[$0.id] }.sorted { $0.sectorStart < $1.sectorStart }
            guard kids.count > 1 else { continue }
            for (a, b) in zip(kids, kids.dropFirst()) {
                #expect(a.sectorEnd <= b.sectorStart + 1e-4, "overlap under \(parent.id): \(a.nodeID) / \(b.nodeID)")
            }
        }
    }

    @Test func timeAxisIsNormalised() throws {
        let layout = engine.layout(graph)
        var sawLow = false, sawHigh = false
        for (_, p) in layout.placements {
            #expect(p.position4.w >= 0 && p.position4.w <= 1)
            if p.position4.w < 0.05 { sawLow = true }
            if p.position4.w > 0.95 { sawHigh = true }
        }
        #expect(sawLow && sawHigh, "oldest file should map to 0 and newest to 1")
        let newest = try #require(graph["OrbitNotes/Features/Notes/Views/NotesListView.swift"])
        let oldest = try #require(graph["OrbitNotes/Core/Extensions/Collection+Safe.swift"])
        #expect(layout[newest.id]?.position4.w == 1)
        #expect(layout[oldest.id]?.position4.w == 0)
    }

    @Test func nonSpatialNodesInheritPosition() throws {
        let layout = engine.layout(graph)
        let fn = try #require(graph.nodes(ofKind: .function).first)
        let type = try #require(graph.parent(of: fn.id))
        let a = try #require(layout[fn.id]), b = try #require(layout[type.id])
        #expect(a.position4.x == b.position4.x && a.position4.y == b.position4.y && a.position4.z == b.position4.z)
        #expect(a.radius == 0)
    }

    @Test func projectionIsContinuous() throws {
        let layout = engine.layout(graph)
        let id: NodeID = "OrbitNotes/Data/Network/SyncClient.swift"
        let p = try #require(layout[id])
        let at0 = try #require(layout.position3(for: id, timeDial: 0))
        #expect(at0 == SIMD3(p.position4.x, p.position4.y, p.position4.z))
        let half = try #require(layout.position3(for: id, timeDial: 0.5))
        let full = try #require(layout.position3(for: id, timeDial: 1))
        #expect(half != at0)
        // Displacement grows linearly with the dial: |full − 0| ≈ 2 · |half − 0|
        #expect(abs(simd_length(full - at0) - 2 * simd_length(half - at0)) < 1e-4)
        // A tiny dial change moves the node only slightly.
        let nearly = try #require(layout.position3(for: id, timeDial: 0.01))
        #expect(simd_length(nearly - at0) < 0.05)
        // Negative dial pulls the opposite way.
        let neg = try #require(layout.position3(for: id, timeDial: -0.5))
        #expect(simd_length((neg - at0) + (half - at0)) < 1e-4)
    }

    @Test func layoutIsDeterministic() {
        let a = engine.layout(graph)
        let b = engine.layout(graph)
        #expect(a.placements == b.placements)
        #expect(RadialShellLayout.unitHash("abc") == RadialShellLayout.unitHash("abc"))
        #expect(RadialShellLayout.unitHash("abc") != RadialShellLayout.unitHash("abd"))
    }

    @Test func largeSiblingCountsSpreadOverSubRings() throws {
        var nodes: [CodeNode] = [CodeNode(id: "R", name: "R", kind: .module, path: "R")]
        var edges: [CodeEdge] = []
        for i in 0..<60 {
            let id = NodeID("R/f\(i).swift")
            nodes.append(CodeNode(id: id, name: "f\(i).swift", kind: .file, path: id.raw, parent: "R", lineCount: 10 + i))
            edges.append(CodeEdge(from: "R", to: id, kind: .contains))
        }
        let g = CodeGraph(projectName: "R", rootID: "R", nodes: nodes, edges: edges)
        let layout = engine.layout(g)
        // Round to 10 cm so float noise does not split a ring in two.
        let radii = Set(g.nodes(ofKind: .file).compactMap { layout[$0.id] }.map { (simd_length(SIMD2($0.position4.x, $0.position4.z)) * 10).rounded() })
        #expect(radii.count == 2, "60 siblings should alternate between two sub-rings, got \(radii)")
        let centroid = try #require(layout.centroid(of: g.nodes(ofKind: .file).map(\.id)))
        #expect(simd_length(SIMD2(centroid.x, centroid.z)) < 0.5, "siblings fill the whole circle")
    }

    @Test func emptyGraphProducesEmptyLayout() {
        let g = CodeGraph(projectName: "E", rootID: "missing", nodes: [], edges: [])
        let layout = engine.layout(g)
        #expect(layout.placements.isEmpty)
        #expect(layout.shellCount == 0)
    }
}
