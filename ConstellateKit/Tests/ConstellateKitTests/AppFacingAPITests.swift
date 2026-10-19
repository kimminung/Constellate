import Foundation
import simd
import Testing
import ConstellateKit   // deliberately NOT `@testable` — see below.

/// Compile-time guard for the app target.
///
/// Every other Kit test uses `@testable import`, which also sees `internal` members — so a missing `public`
/// (an implicit default / memberwise init, a helper left internal) passes the whole Kit suite and only fails once
/// Xcode builds the app. Imports are file-scoped, so this file sees exactly what the app sees: it touches the
/// Kit API that the app's relation layer, star glyphs, Inspector, legend and session sync call. If it stops
/// compiling, fix the access level in the Kit (don't add `@testable` here).
@Suite struct AppFacingAPITests {
    let graph = SampleGraph.orbitNotes()

    /// `EdgeRenderer` / `FlowParticles` / `ConstellationSceneController.rebuildEdges()`.
    @Test func relationLayerSurface() throws {
        var scene = EdgeScene()   // EdgeRenderer's empty state before the first build and after removeAll()
        #expect(scene.batches.isEmpty && scene.flows.isEmpty && scene.related.isEmpty)

        let layout = ConstellationLayoutEngine(style: .wall).layout(graph)
        let insights = GraphInsights(graph: graph)
        var options = EdgeSceneOptions()
        options.mode = .all
        options.hidden = [.uses]
        options.focus = [graph.rootID]
        options.bulgeInward = true
        options.timeDial = 0.25
        options.reduceMotion = false
        options.insights = insights
        #expect(options.particleCap > 0)
        scene = EdgeSceneBuilder.build(graph: graph, layout: layout, options: options)

        #expect(!scene.sortedBatchKeys.isEmpty)
        for key in scene.sortedBatchKeys {
            let tube = try #require(scene.batches[key])
            #expect(!tube.isEmpty && tube.positions.count == tube.uvs.count && tube.normals.count == tube.positions.count)
            #expect(tube.indices.count == tube.triangleCount * 3)
            _ = "edges:\(key.relation?.rawValue ?? "contains"):\(key.emphasis)\(key.isCycle ? ":cycle" : "")"
            #expect(key.opacity > 0 && key.opacity <= 1)
            _ = key.color(theme: .dark).withAlpha(1)
        }
        _ = EdgeBatchKey.cycleColor.hexString
        _ = (scene.drawnCounts, scene.totalCounts, scene.cycleEdgeCount, scene.related)

        for flow in scene.flows {
            #expect(flow.relation.style.flow && flow.particleCount >= 0 && flow.speed > 0)
            let position = flow.point(atFraction: 0.5)
            #expect(position.x.isFinite && flow.totalLength > 0)
            _ = (flow.emphasis == .focus, flow.relation.style.color)   // `lightened` is app-side (ColorBridge)
        }
    }

    /// `NodeStarFactory`, `CodeNodeEntity.setStar` and the scene controller's star ranking / cycle halos.
    @Test func starSurface() throws {
        let layout = ConstellationLayoutEngine(style: .celestial).layout(graph)
        let insights = GraphInsights(graph: graph)
        #expect(StarEncoder.allGlyphNames.count >= 14 && StarEncoder.haloGlyphName == "Star_Halo")
        let node = try #require(graph.nodes.first { $0.kind == .file && layout.placements[$0.id] != nil })
        let placement = try #require(layout.placements[node.id])
        let star = StarEncoder.appearance(for: node, theme: .dark, fanIn: insights.fanIn(of: node.id),
                                          recency: placement.position4.w, inCycle: false)
        #expect(StarEncoder.allGlyphNames.contains(star.glyph))
        #expect(star.size > 0 && star.glow >= 0 && star.glow <= 1 && !star.inCycle)
        _ = star.color.hexString
        let anchor = StarEncoder.anchor(cardWidth: 0.3, size: star.size)
        #expect(anchor.x < 0 && anchor.y > 0, "above the card's top-left corner")
        #expect(star.size / StarEncoder.glyphExtent > 0)
        _ = (Set(insights.cycleMembers(of: node.id)), insights.file(of: node.id), insights.fanOut(of: node.id))
        _ = layout.project(placement, timeDial: 0.4)
    }

    /// Inspector (coupling grid, grouped relations), card chips, host-AI relation summary.
    @Test func inspectorSurface() throws {
        let insights = GraphInsights(graph: graph)
        let file = try #require(graph.nodes.first { $0.kind == .file && !RelationDigest.groups(for: $0.id, in: graph).isEmpty })
        let metrics: NodeMetrics = insights.metrics(for: file.id)
        _ = (metrics.fanIn, metrics.fanOut, metrics.impact, metrics.cycleIndex, metrics.instability)
        let groups: [RelationGroup] = RelationDigest.groups(for: file.id, in: graph)
        for group in groups {
            #expect(!group.phrase.isEmpty && group.total >= group.nodes.count)
            _ = (group.id, group.relation.style.labelEn, group.outgoing)
        }
        for node in graph.nodes {
            if let role = node.role { _ = (role.style.label, role.style.color, role.style.symbol) }
        }
        for edge in graph.edges { _ = edge.semantic }
    }

    /// Layout picker, relation legend / mode picker, session sync.
    @Test func controlsAndSessionSurface() throws {
        for style in LayoutStyle.allCases {
            #expect(LayoutStyle(rawValue: style.rawValue) == style)
            #expect(!style.label.isEmpty && !style.symbol.isEmpty && !style.axes.isEmpty && style.id == style.rawValue)
        }
        _ = LayoutStyle.appDefault
        for mode in RelationDisplayMode.allCases {
            #expect(RelationDisplayMode(rawValue: mode.rawValue) == mode && mode.id == mode.rawValue)
            _ = (mode.label, mode.symbol, mode.next)
        }
        for kind in RelationKind.legendOrder {
            #expect(RelationKind(rawValue: kind.rawValue) == kind)
            let style = kind.style
            _ = (style.label, style.labelEn, style.hint, style.dashed, style.flow, style.color)
        }
        let sphere = ConstellationLayoutEngine(style: .spiral).layout(graph).boundingSphere
        #expect(sphere.radius > 0 && sphere.center.y.isFinite)

        for message in [ConstellateMessage.layoutStyle(.celestial), .relationMode(.focus)] {
            let data = try JSONEncoder().encode(message)
            #expect(try JSONDecoder().decode(ConstellateMessage.self, from: data) == message)
        }
    }
}
