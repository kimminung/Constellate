import Foundation
import simd

/// `.spiral` — port of CoulsonPortfolioWeb `layouts/spiral.js`.
///
/// Original: files in path order climb a helix (12 per turn, radius growing slightly per file, 0.7 units up per
/// file); a folder label sits above its first file, pulled toward the axis.
///
/// Constellate keeps the helix and reading order (types follow their file) but bounds it for a standing viewer:
/// the helix climbs at most ~10 turns, cards per turn grow with the project so neighbours never overlap, and the
/// radius grows with the turn count instead of per file (the original's `+0.08·i` explodes on large repos).
/// Folders are stops on the helix right before their files (the original floated them above the first file, where
/// nested folders landed on top of each other).
struct SpiralLayout {
    let context: LayoutContext
    private var configuration: LayoutConfiguration { context.configuration }

    func run() -> ConstellationLayout {
        let graph = context.graph
        guard let root = graph.root else { return .empty }
        let items = context.preorderSpatial().filter { $0.kind != .module }
        let n = max(items.count, 1)

        let widths = items.map { 2 * context.cardRadius(for: $0) }.sorted()
        let typical = widths.isEmpty ? 0.3 : widths[min(widths.count - 1, Int(Float(widths.count) * 0.75))]
        let spacing = typical + configuration.cardGap * 0.7            // arc length between neighbours
        let perTurn = max(12, Int((Float(n) / 10).rounded(.up)))      // ≤ 10 turns
        let baseRadius = max(2.2, Float(perTurn) * spacing / (2 * .pi))
        let pitch = typical * 0.6875 + configuration.cardGap * 0.9     // height gained per turn
        let rise = pitch / Float(perTurn)
        let step = 2 * Float.pi / Float(perTurn)
        let bottom = configuration.floorClearance + 0.15

        var placements: [NodeID: LayoutPlacement] = [:]
        var top = bottom
        for (i, item) in items.enumerated() {
            let a = Float(i) * step
            let r = baseRadius * (1 + 0.25 * Float(i) / Float(n))
            let y = bottom + Float(i) * rise
            top = max(top, y)
            // a = 0 → straight ahead (−Z), turning to the right.
            let p = SIMD3<Float>(r * sin(a), y, -r * cos(a))
            placements[item.id] = context.placement(item, at: p, shell: graph.depth(of: item.id), sectorStart: a, sectorEnd: a)
        }

        placements[root.id] = context.placement(root, at: SIMD3(0, top + pitch * 1.2, 0), shell: 0, sectorStart: 0, sectorEnd: 2 * .pi)

        return context.finish(&placements, style: .spiral, center: SIMD3(0, (bottom + top) / 2, 0), projection: LayoutStyle.spiral.timeProjection) { node in
            let a = LayoutContext.unitHash(node.id.raw) * 2 * .pi
            return SIMD3(baseRadius * sin(a), bottom, -baseRadius * cos(a))
        }
    }
}
