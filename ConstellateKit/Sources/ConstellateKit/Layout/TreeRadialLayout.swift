import Foundation
import simd

/// `.treeRadial` — port of CoulsonPortfolioWeb `layouts/treeRadial.js`.
///
/// Original: the root sits in the centre, each depth is a ring (`RING` per depth), every node owns an angular span
/// proportional to its *leaf count* (files), and a ring grows when its files would not fit
/// (`radius = max(depth·RING, leaves·MIN_ARC / 2π)`). Folder labels sit just inside their ring and higher than the
/// files; panels face outward.
///
/// Constellate keeps the rule set and units it to metres (`RING` = `shellSpacing`, `MIN_ARC` = widest card + gap).
/// Two additions: file heights follow the architecture layer bands (the same "y = layer" rule as `.shells`, so a
/// developer reads height the same way in every style), and a file's types stand in a short column just behind it
/// instead of competing for ring space.
struct TreeRadialLayout {
    let context: LayoutContext
    private var configuration: LayoutConfiguration { context.configuration }

    /// Height of folder hubs above the layer bands (portfolio: `y: 3.6` for directories vs ~0 for files).
    private var folderHeight: Float { (configuration.layerHeights.values.max() ?? 2.1) + configuration.verticalJitter + 0.25 }

    func run() -> ConstellationLayout {
        let graph = context.graph
        guard let root = graph.root else { return .empty }

        // Leaf (file) counts per subtree and per depth.
        var leafCount: [NodeID: Int] = [:]
        var filesPerDepth: [Int: Int] = [:]
        var widest: Float = 0
        func count(_ node: CodeNode, depth: Int) -> Int {
            if node.kind == .file {
                leafCount[node.id] = 1
                filesPerDepth[depth, default: 0] += 1
                widest = max(widest, 2 * context.cardRadius(for: node))
                return 1
            }
            var sum = 0
            for child in context.spatialChildren(of: node.id) where child.kind == .folder || child.kind == .file || child.kind == .module {
                sum += count(child, depth: depth + 1)
            }
            leafCount[node.id] = sum
            return sum
        }
        _ = count(root, depth: 0)

        let ring = configuration.shellSpacing
        let minArc = max(0.45, widest * 0.75 + configuration.cardGap)
        func radiusAt(_ depth: Int) -> Float {
            let needed = Float(filesPerDepth[depth] ?? 0) * minArc / (2 * .pi)
            return max(Float(depth) * ring, needed)
        }

        var placements: [NodeID: LayoutPlacement] = [:]
        func place(_ node: CodeNode, depth: Int, start: Float, end: Float, siblingIndex: Int = 0) {
            let mid = (start + end) / 2
            if node.kind == .file {
                let r = radiusAt(depth)
                let y = context.layerHeight(for: node)
                let p = SIMD3(r * cos(mid), y, -r * sin(mid))
                placements[node.id] = context.placement(node, at: p, shell: depth, sectorStart: start, sectorEnd: end)
                // Types (nested ones included): a short column just behind the file (outward), centred on its height.
                let types = graph.subtree(of: node.id).filter { $0.kind.isSpatial && $0.id != node.id }
                for (k, type) in types.enumerated() {
                    let rowHeight = 2 * context.cardRadius(for: type) * 0.6875 + 0.06
                    let offset = (Float(k) - Float(types.count - 1) / 2) * rowHeight
                    let rt = r + ring * 0.42
                    let pt = SIMD3(rt * cos(mid), max(configuration.floorClearance, y + offset), -rt * sin(mid))
                    placements[type.id] = context.placement(type, at: pt, shell: depth + 1, sectorStart: start, sectorEnd: end)
                }
                return
            }
            // Hub: just inside its ring (original), pushed out until the hub card fits inside its own angular span
            // (never past the next ring), stepped down per depth, and alternately raised so adjacent hubs on
            // narrow spans don't collide.
            let inner = depth == 0 ? 0 : radiusAt(depth) - ring * 0.45
            let fit = (2 * context.cardRadius(for: node) + 0.12) / max(0.05, end - start)
            let r = depth == 0 ? 0 : min(max(inner, fit), max(inner, radiusAt(depth + 1) - ring * 0.3))
            let lift: Float = siblingIndex.isMultiple(of: 2) ? 0 : 0.28
            let y = depth == 0 ? folderHeight + 0.35 : folderHeight - Float(depth - 1) * 0.18 + lift
            placements[node.id] = context.placement(node, at: SIMD3(r * cos(mid), y, -r * sin(mid)), shell: depth, sectorStart: start, sectorEnd: end)
            let children = context.spatialChildren(of: node.id).filter { $0.kind == .folder || $0.kind == .file }
            // Sum of the children's shares (the original divided by the leaf count, which overflows the span
            // when a child folder has no files).
            let total = Float(max(1, children.reduce(0) { $0 + max(leafCount[$1.id] ?? 0, 1) }))
            var cursor = start
            for (index, child) in children.enumerated() {
                let span = (end - start) * Float(max(leafCount[child.id] ?? 0, 1)) / total
                place(child, depth: depth + 1, start: cursor, end: cursor + span, siblingIndex: index)
                cursor += span
            }
        }
        place(root, depth: 0, start: 0, end: 2 * .pi)

        return context.finish(&placements, style: .treeRadial, center: .zero, projection: LayoutStyle.treeRadial.timeProjection) { node in
            let a = LayoutContext.unitHash(node.id.raw) * 2 * .pi
            let r = radiusAt(max(1, graph.depth(of: node.id)))
            return SIMD3(r * cos(a), context.layerHeight(for: node), -r * sin(a))
        }
    }
}
