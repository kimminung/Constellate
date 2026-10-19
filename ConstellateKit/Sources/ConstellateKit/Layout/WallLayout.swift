import Foundation
import simd

/// `.wall` — port of CoulsonPortfolioWeb `layouts/grid.js`, curved into a cylindrical wall.
///
/// Original: files in path order on a near-square grid (`cols = ⌈√(n·1.4)⌉`), every panel facing +Z, folder
/// labels above their direct files' centre.
///
/// Constellate keeps the grid maths but bends it around the viewer (the portfolio's UI calligram wall already
/// curves slightly): every card stays at the same distance, so the edges of a wide wall are as readable as its
/// middle, and the wall never extends below the floor. Types follow their file in the reading order, and folders
/// are *header cells* in that order (a folder card, then its files) instead of labels floating above the grid —
/// floating labels of neighbouring folders collide on dense walls; header cells never do.
struct WallLayout {
    let context: LayoutContext
    private var configuration: LayoutConfiguration { context.configuration }

    func run() -> ConstellationLayout {
        let graph = context.graph
        guard let root = graph.root else { return .empty }
        let items = context.preorderSpatial().filter { $0.kind != .module }
        let n = max(items.count, 1)

        // Cell size from the 90th-percentile card so most cards get breathing room without huge gaps.
        let widths = items.map { 2 * context.cardRadius(for: $0) }.sorted()
        let p90 = widths.isEmpty ? 0.3 : widths[min(widths.count - 1, Int(Float(widths.count) * 0.9))]
        let cellW = p90 + configuration.cardGap * 0.6
        let cellH = p90 * 0.6875 + configuration.cardGap * 0.55
        let cols = max(1, Int((Float(n) * 1.4).squareRoot().rounded(.up)))
        let rows = Int((Float(n) / Float(cols)).rounded(.up))
        // Radius so the wall spans at most ~160°; never closer than 3 m.
        let radius = max(3.0, Float(cols) * cellW / (.pi * 0.9))
        let step = cellW / radius
        let center = SIMD3<Float>(0, configuration.eyeHeight, 0)
        let height = Float(rows - 1) * cellH
        let top = max(configuration.eyeHeight + height / 2, configuration.floorClearance + height)

        func point(angle: Float, y: Float, r: Float = radius) -> SIMD3<Float> {
            // angle 0 = straight ahead (−Z), positive to the right.
            SIMD3(r * sin(angle), y, -r * cos(angle))
        }

        var placements: [NodeID: LayoutPlacement] = [:]
        for (i, item) in items.enumerated() {
            let c = i % cols
            let r = i / cols
            let angle = (Float(c) - Float(cols - 1) / 2) * step
            let y = top - Float(r) * cellH
            let p = point(angle: angle, y: y)
            placements[item.id] = context.placement(item, at: p, shell: graph.depth(of: item.id), sectorStart: angle, sectorEnd: angle)
        }

        placements[root.id] = context.placement(root, at: point(angle: 0, y: top + cellH * 1.4, r: radius - 0.35), shell: 0, sectorStart: 0, sectorEnd: 0)

        return context.finish(&placements, style: .wall, center: center, projection: LayoutStyle.wall.timeProjection) { node in
            let a = (LayoutContext.unitHash(node.id.raw) - 0.5) * Float(cols) * step
            return point(angle: a, y: configuration.eyeHeight)
        }
    }
}
