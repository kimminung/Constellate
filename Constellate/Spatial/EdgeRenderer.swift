import ConstellateKit
import Foundation
import simd

/// Picks and lays out edges as merged thin-box geometry, one batch per edge kind (built off the main actor).
nonisolated enum EdgeRenderer {

    struct Batch: Sendable {
        var kind: EdgeKind
        var geometry: LineGeometry
    }

    static let edgeCap = 1500
    static let treeThickness: Float = 0.004
    static let relationThickness: Float = 0.0075

    /// Priority order when capping: structural relations first, then the tree.
    private static let priority: [EdgeKind] = [.inherits, .references, .calls, .imports, .contains]

    static func batches(graph: CodeGraph, layout: ConstellationLayout, timeDial: Float, cap: Int = edgeCap) -> [Batch] {
        var chosen: [CodeEdge] = []
        chosen.reserveCapacity(min(cap, graph.edges.count))
        var byKind: [EdgeKind: [CodeEdge]] = [:]
        for e in graph.edges { byKind[e.kind, default: []].append(e) }
        for kind in priority {
            guard chosen.count < cap, let list = byKind[kind] else { continue }
            let room = cap - chosen.count
            if list.count <= room {
                chosen.append(contentsOf: list)
            } else {
                // Keep the heaviest edges when we have to drop some.
                chosen.append(contentsOf: list.sorted { $0.weight > $1.weight }.prefix(room))
            }
        }

        var geometries: [EdgeKind: LineGeometry] = [:]
        for e in chosen {
            guard let a = layout.position3(for: e.from, timeDial: timeDial),
                  let b = layout.position3(for: e.to, timeDial: timeDial) else { continue }
            let thickness = e.kind == .contains ? treeThickness : relationThickness
            // Relation edges arc slightly upward so they read as separate from tree edges.
            if e.kind == .contains {
                geometries[e.kind, default: LineGeometry()].addSegment(from: a, to: b, thickness: thickness)
            } else {
                let mid = (a + b) / 2 + SIMD3<Float>(0, min(0.35, simd_distance(a, b) * 0.12), 0)
                var g = geometries[e.kind, default: LineGeometry()]
                g.addSegment(from: a, to: mid, thickness: thickness)
                g.addSegment(from: mid, to: b, thickness: thickness)
                geometries[e.kind] = g
            }
        }
        return priority.compactMap { kind in geometries[kind].map { Batch(kind: kind, geometry: $0) } }
    }
}
