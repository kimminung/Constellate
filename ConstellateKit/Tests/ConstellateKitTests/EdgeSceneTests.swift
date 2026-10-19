import Foundation
import simd
import Testing
@testable import ConstellateKit

/// Relation arcs (the portfolio's `rebuildEdges()` port) and the dependency insights that colour them.
@Suite struct EdgeSceneTests {
    let graph = SampleGraph.orbitNotes()
    var layout: ConstellationLayout { ConstellationLayoutEngine(style: .celestial).layout(graph) }

    private func validate(_ mesh: TubeMesh) {
        #expect(mesh.positions.count == mesh.normals.count && mesh.positions.count == mesh.uvs.count)
        #expect(mesh.indices.count % 3 == 0)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
        #expect(mesh.uvs.allSatisfy { $0.x >= -1e-4 && $0.x <= 1 + 1e-4 })
        #expect(mesh.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
    }

    @Test func allModeDrawsEveryKindWithValidMeshes() {
        let scene = EdgeSceneBuilder.build(graph: graph, layout: layout, options: EdgeSceneOptions())
        #expect(!scene.batches.isEmpty)
        for (_, mesh) in scene.batches { validate(mesh) }
        let total = graph.edges.filter { $0.kind != .contains }.count
        #expect(scene.totalCounts.values.reduce(0, +) == total)
        #expect(scene.drawnCounts.values.reduce(0, +) <= total)
        #expect(scene.batches.keys.contains { $0.relation == nil }, "tree lines")
        #expect(scene.batches.keys.contains { $0.relation == .binds })
        #expect(scene.related.isEmpty, "nothing focused → nothing dims")
        #expect(!scene.flows.isEmpty && scene.flows.allSatisfy { $0.relation.style.flow })
    }

    @Test func offAndFocusModes() throws {
        var options = EdgeSceneOptions()
        options.mode = .off
        let off = EdgeSceneBuilder.build(graph: graph, layout: layout, options: options)
        #expect(off.batches.keys.allSatisfy { $0.relation == nil } && off.flows.isEmpty)

        options.mode = .focus
        let idle = EdgeSceneBuilder.build(graph: graph, layout: layout, options: options)
        #expect(idle.drawnCounts.isEmpty, "focus mode with no focus draws no relations")

        let file: NodeID = "OrbitNotes/Features/Notes/Views/NotesListView.swift"
        options.focus = [file]
        let focused = EdgeSceneBuilder.build(graph: graph, layout: layout, options: options)
        #expect(focused.drawnCounts.values.reduce(0, +) > 0)
        #expect(focused.batches.keys.filter { $0.relation != nil }.allSatisfy { $0.emphasis == .focus })
        #expect(focused.related.contains(file))
        // The file's type counts as part of the focus (its own edges light up too).
        let type = try #require(graph.children(of: file).first { $0.kind == .type })
        #expect(EdgeSceneBuilder.expandFocus([file], in: graph).contains(type.id))
        #expect(focused.related.contains(type.id), "the selected file's own type card never dims")

        // All mode + focus: focus edges loud, the rest faint.
        options.mode = .all
        let mixed = EdgeSceneBuilder.build(graph: graph, layout: layout, options: options)
        #expect(mixed.batches.keys.contains { $0.emphasis == .focus } && mixed.batches.keys.contains { $0.emphasis == .faint })
        #expect(EdgeBatchKey(relation: .binds, emphasis: .focus).opacity > EdgeBatchKey(relation: .binds, emphasis: .faint).opacity)
    }

    @Test func hiddenKindsAndCaps() {
        var options = EdgeSceneOptions()
        options.hidden = [.uses]
        options.particleCap = 5
        let scene = EdgeSceneBuilder.build(graph: graph, layout: layout, options: options)
        #expect(scene.drawnCounts[.uses] == nil)
        #expect((scene.totalCounts[.uses] ?? 0) > 0, "legend still counts hidden kinds")
        #expect(scene.flows.reduce(0) { $0 + $1.particleCount } <= 5)
        options.reduceMotion = true
        options.particleCap = 40
        let calm = EdgeSceneBuilder.build(graph: graph, layout: layout, options: options)
        #expect(calm.flows.reduce(0) { $0 + $1.particleCount } <= 10)
    }

    @Test func lanesSeparateKindsBetweenTheSameCards() {
        let a = SIMD3<Float>(-1, 1.5, -3), b = SIMD3<Float>(1, 1.6, -3.2), c = SIMD3<Float>(0, 1.45, 0)
        let kinds: [RelationKind] = [.uses, .conforms, .composes, .binds, .creates, .presents, .notifies]
        let mids: [SIMD3<Float>] = kinds.map { (kind: RelationKind) -> SIMD3<Float> in
            let pts = EdgeSceneBuilder.arc(from: a, to: b, center: c, style: kind.style, inward: false)
            return pts[pts.count / 2]
        }
        for i in 0..<mids.count {
            for j in (i + 1)..<mids.count {
                #expect(simd_distance(mids[i], mids[j]) > 0.05, "\(kinds[i]) vs \(kinds[j])")
            }
        }
        // Endpoints are exact; inward arcs come toward the centre, outward ones go away.
        let out = EdgeSceneBuilder.arc(from: a, to: b, center: c, style: RelationKind.uses.style, inward: false)
        let inn = EdgeSceneBuilder.arc(from: a, to: b, center: c, style: RelationKind.uses.style, inward: true)
        #expect(out.first == a && out.last == b)
        let mid = (a + b) / 2
        #expect(simd_distance(out[out.count / 2], c) > simd_distance(mid, c))
        #expect(simd_distance(inn[inn.count / 2], c) < simd_distance(mid, c))
    }

    @Test func flowsRunInDataDirection() throws {
        let scene = EdgeSceneBuilder.build(graph: graph, layout: layout, options: EdgeSceneOptions())
        let binds = try #require(graph.edges.first { $0.relation == .binds })
        let from = try #require(layout.position3(for: binds.from)), to = try #require(layout.position3(for: binds.to))
        let path = try #require(scene.flows.first { $0.relation == .binds && simd_distance($0.points.first!, to) < 1e-4 })
        #expect(simd_distance(path.points.last!, from) < 1e-4, "binds: source → observing view")
        #expect(simd_distance(path.point(atFraction: 0), to) < 1e-4)
        #expect(simd_distance(path.point(atFraction: 0.999), from) < 0.05)
        #expect(simd_distance(path.point(atFraction: 1.25), path.point(atFraction: 0.25)) < 1e-4, "wraps")
    }

    @Test func dashesAndArrows() {
        let pts = (0...40).map { SIMD3<Float>(Float($0) * 0.05, 0, 0) }  // 2 m line
        let pieces = EdgeSceneBuilder.dashes(pts)
        #expect(pieces.count == Int((2 / (EdgeSceneBuilder.dash + EdgeSceneBuilder.gap)).rounded(.up)))
        #expect(pieces.allSatisfy { $0.uStart < $0.uEnd && $0.uEnd <= 1 + 1e-5 })
        var mesh = TubeMesh()
        EdgeSceneBuilder.appendArrow(to: &mesh, along: pts, tubeRadius: 0.003)
        validate(mesh)
        let tip = mesh.positions.max { $0.x < $1.x }!
        #expect(tip.x < 2 && tip.x > 1.8, "tip just before the end")
    }

    @Test func tubeFramesDoNotCollapse() {
        // A curve that turns 180°: the tube keeps a constant radius everywhere.
        let pts = (0...30).map { i -> SIMD3<Float> in let a = Float(i) / 30 * .pi; return SIMD3(cos(a), sin(a), 0) }
        var mesh = TubeMesh()
        mesh.appendTube(pts, radius: 0.01, sides: 4, uStart: 0, uEnd: 1)
        validate(mesh)
        for (i, p) in pts.enumerated() {
            for k in 0..<4 {
                #expect(abs(simd_distance(mesh.positions[i * 4 + k], p) - 0.01) < 1e-4)
            }
        }
    }

    @Test func insightsFindCyclesImpactAndStability() throws {
        func file(_ name: String) -> CodeNode { CodeNode(id: NodeID("P/\(name).swift"), name: name, kind: .file, path: "P/\(name).swift", parent: "P", lineCount: 10) }
        let names = ["A", "B", "C", "D", "E"]
        var nodes = [CodeNode(id: "P", name: "P", kind: .module, path: "P")] + names.map(file)
        nodes.append(CodeNode(id: "P/A.swift#A", name: "A", kind: .type, path: "P/A.swift", parent: "P/A.swift"))
        var edges = names.map { CodeEdge(from: "P", to: NodeID("P/\($0).swift"), kind: .contains) }
        edges.append(CodeEdge(from: "P/A.swift", to: "P/A.swift#A", kind: .contains))
        func ref(_ a: String, _ b: String, _ r: RelationKind = .uses) -> CodeEdge { CodeEdge(from: NodeID("P/\(a).swift"), to: NodeID("P/\(b).swift"), kind: .references, relation: r) }
        edges += [ref("A", "B"), ref("B", "C", .creates), ref("C", "A", .binds), ref("D", "A"), ref("E", "D", .notifies)]
        let g = CodeGraph(projectName: "P", rootID: "P", nodes: nodes, edges: edges)
        let insights = GraphInsights(graph: g)
        #expect(insights.cycles == [["P/A.swift", "P/B.swift", "P/C.swift"]])
        #expect(insights.cycle(containing: "P/A.swift#A") == 0, "types inherit their file's cycle")
        #expect(insights.cycle(containing: "P/D.swift") == nil)
        #expect(insights.isCycleEdge(ref("A", "B")) && !insights.isCycleEdge(ref("D", "A")))
        let impact = insights.impact(of: "P/A.swift")
        #expect(impact["P/C.swift"] == 1 && impact["P/D.swift"] == 1 && impact["P/B.swift"] == 2)
        #expect(impact["P/E.swift"] == nil, "notifications are not compile-time dependencies")
        #expect(insights.reach(of: "P/D.swift", maxDepth: 1) == ["P/A.swift": 1])
        let m = insights.metrics(for: "P/D.swift")
        #expect(m.fanIn == 0 && m.fanOut == 1 && m.instability == 1)
        let a = insights.metrics(for: "P/A.swift")
        #expect(a.fanIn == 2 && a.fanOut == 1 && a.cycleIndex == 0 && a.impact == 3)

        // Cycles are diagnosed on demand: nothing is painted until a cycle member is focused…
        var options = EdgeSceneOptions()
        options.insights = insights
        let l = ConstellationLayoutEngine(style: .celestial).layout(g)
        let quiet = EdgeSceneBuilder.build(graph: g, layout: l, options: options)
        #expect(quiet.cycleEdgeCount == 0 && !quiet.batches.keys.contains { $0.isCycle })
        // …then the whole loop lights up, even in focus mode (B → C and C → A do not touch A's type).
        options.focus = ["P/A.swift#A"]
        options.mode = .focus
        let scene = EdgeSceneBuilder.build(graph: g, layout: l, options: options)
        #expect(scene.cycleEdgeCount == 3)
        #expect(scene.batches.keys.contains { $0.isCycle })
        #expect(scene.related.isSuperset(of: ["P/B.swift", "P/C.swift"]))
    }

    @Test func sampleGraphInsightsAreSane() {
        let insights = GraphInsights(graph: graph)
        for file in graph.nodes(ofKind: .file) {
            let m = insights.metrics(for: file.id)
            if let i = m.instability { #expect(i >= 0 && i <= 1) }
            #expect(m.impact >= m.fanIn)
        }
        // Note.swift is the most depended-on model in Orbit Notes.
        let note = insights.metrics(for: "OrbitNotes/Domain/Models/Note.swift")
        #expect(note.fanIn >= 10)
        #expect((note.instability ?? 1) < 0.3, "a stable core type")
    }
}

@Suite struct StarEncoderTests {
    @Test func channelsEncodeRoleLayerCouplingAndRecency() throws {
        let graph = SampleGraph.orbitNotes()
        let view = try #require(graph["OrbitNotes/Features/Notes/Views/NotesListView.swift"])
        let a = StarEncoder.appearance(for: view, theme: .dark, fanIn: 0, recency: 0, inCycle: false)
        let b = StarEncoder.appearance(for: view, theme: .dark, fanIn: 15, recency: 1, inCycle: true)
        #expect(a.glyph == "Star_View" && a.color == ConstellateTheme.dark.color(for: .presentation))
        #expect(b.size > a.size && b.size <= 0.11)
        #expect(b.glow > a.glow && b.glow <= 1)
        #expect(StarEncoder.appearance(for: try #require(graph["OrbitNotes/Data"]), theme: .dark, fanIn: 0, recency: 0.5, inCycle: false).glyph == "Star_Folder")
        #expect(StarEncoder.appearance(for: try #require(graph.root), theme: .dark, fanIn: 0, recency: 0.5, inCycle: false).glyph == "Star_Module")
        #expect(Set(StarEncoder.allGlyphNames).count == StarEncoder.allGlyphNames.count)
    }
}
