import Foundation
import simd

/// A self-contained, renderer-agnostic picture of one constellation: every spatial node with its position, card
/// size, role glyph and colours, plus every drawn relation arc as a polyline. Codable as plain JSON.
///
/// Uses: the Blender pipeline renders README / design images from it (`Blender/scripts/render_graph.py` reads
/// `Blender/data/*.json`), tests diff it, and it is a handy debugging dump of what the scene controller will draw
/// (`ConstellationSnapshot.make(...)` takes the same inputs the app uses).
public struct ConstellationSnapshot: Codable, Sendable {
    public struct Node: Codable, Sendable {
        public var id: String
        public var name: String
        public var kind: String
        public var role: String?
        public var layer: String
        /// Y-up metres (RealityKit space).
        public var position: [Float]
        /// Card width in metres.
        public var cardWidth: Float
        public var recency: Float
        public var glyph: String
        public var starColor: String
        public var starSize: Float
        public var starGlow: Float
        public var layerColor: String
        /// First lines of source for card textures (sample graphs only; empty for real projects).
        public var preview: [String]
    }

    public struct Arc: Codable, Sendable {
        /// Relation raw value, or "contains" for tree lines.
        public var relation: String
        public var emphasis: String
        public var isCycle: Bool
        public var color: String
        public var opacity: Float
        public var dashed: Bool
        public var flow: Bool
        /// Polyline in flow direction, Y-up metres.
        public var points: [[Float]]
    }

    /// One relation kind as the legend shows it (so renders and docs read styles from the Swift source of truth).
    public struct LegendEntry: Codable, Sendable {
        public var relation: String
        public var labelKo: String
        public var labelEn: String
        public var hint: String
        public var color: String
        public var dashed: Bool
        public var flow: Bool
    }

    /// One role glyph (shape legend).
    public struct RoleEntry: Codable, Sendable {
        public var role: String
        public var label: String
        public var glyph: String
        public var color: String
    }

    public var project: String
    public var style: String
    public var center: [Float]
    public var nodes: [Node]
    public var arcs: [Arc]
    public var legend: [LegendEntry]
    public var roles: [RoleEntry]

    /// Relation + role legends in display order.
    public static func legends() -> (relations: [LegendEntry], roles: [RoleEntry]) {
        let relations = RelationKind.legendOrder.map { kind in
            LegendEntry(relation: kind.rawValue, labelKo: kind.style.labelKo, labelEn: kind.style.labelEn, hint: kind.style.hint,
                        color: kind.style.color.hexString, dashed: kind.style.dashed, flow: kind.style.flow)
        }
        let roles = CodeRole.allCases.map { role in
            RoleEntry(role: role.rawValue, label: role.style.label, glyph: role.style.glyph, color: role.style.color.hexString)
        }
        return (relations, roles)
    }

    /// Builds a snapshot with the same inputs the scene controller uses.
    public static func make(graph: CodeGraph, layout: ConstellationLayout, theme: ConstellateTheme = .dark,
                            options: EdgeSceneOptions = EdgeSceneOptions(), previewLines: (NodeID) -> [String] = { _ in [] }) -> ConstellationSnapshot {
        let insights = options.insights ?? GraphInsights(graph: graph)
        var nodes: [Node] = []
        for node in graph.nodes where node.kind.isSpatial {
            guard let p = layout[node.id] else { continue }
            let pos = layout.project(p, timeDial: options.timeDial)
            let star = StarEncoder.appearance(for: node, theme: theme, fanIn: insights.metrics(for: node.id).fanIn,
                                              recency: p.position4.w, inCycle: insights.cycle(containing: node.id) != nil)
            nodes.append(Node(
                id: node.id.raw, name: node.name, kind: node.kind.rawValue, role: node.role?.rawValue, layer: node.layer.rawValue,
                position: [pos.x, pos.y, pos.z], cardWidth: max(0.12, p.radius * 2), recency: p.position4.w,
                glyph: star.glyph, starColor: star.color.hexString, starSize: star.size, starGlow: star.glow,
                layerColor: theme.color(for: node.layer).hexString, preview: previewLines(node.id)
            ))
        }
        // Arcs: rebuild the polylines exactly like EdgeSceneBuilder (one arc per drawn edge).
        var arcs: [Arc] = []
        var opts = options
        opts.insights = insights
        let focus = EdgeSceneBuilder.expandFocus(opts.focus, in: graph)
        for e in graph.edges {
            guard let a = layout.position3(for: e.from, timeDial: opts.timeDial), let b = layout.position3(for: e.to, timeDial: opts.timeDial),
                  simd_distance(a, b) > 0.02 else { continue }
            if e.kind == .contains {
                guard opts.showTree, graph[e.from]?.kind.isSpatial == true, graph[e.to]?.kind.isSpatial == true else { continue }
                let key = EdgeBatchKey(relation: nil, emphasis: focus.isEmpty ? .normal : .faint)
                arcs.append(Arc(relation: "contains", emphasis: "\(key.emphasis)", isCycle: false, color: key.color(theme: theme).hexString,
                                opacity: key.opacity, dashed: false, flow: false, points: [[a.x, a.y, a.z], [b.x, b.y, b.z]]))
                continue
            }
            guard let rel = e.semantic, !opts.hidden.contains(rel), opts.mode != .off else { continue }
            let touches = focus.contains(e.from) || focus.contains(e.to)
            if opts.mode == .focus && !touches { continue }
            let emphasis: EdgeEmphasis = touches ? .focus : (focus.isEmpty ? .normal : .faint)
            let key = EdgeBatchKey(relation: rel, emphasis: emphasis, isCycle: false)
            var pts = EdgeSceneBuilder.arc(from: a, to: b, center: layout.center, style: rel.style, inward: opts.bulgeInward)
            if rel.flowIsReversed { pts.reverse() }
            arcs.append(Arc(relation: rel.rawValue, emphasis: "\(emphasis)", isCycle: false, color: key.color(theme: theme).hexString,
                            opacity: key.opacity, dashed: rel.style.dashed, flow: rel.style.flow, points: pts.map { [$0.x, $0.y, $0.z] }))
        }
        let legends = legends()
        return ConstellationSnapshot(project: graph.projectName, style: layout.style.rawValue,
                                     center: [layout.center.x, layout.center.y, layout.center.z], nodes: nodes, arcs: arcs,
                                     legend: legends.relations, roles: legends.roles)
    }
}
