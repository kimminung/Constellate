import Foundation
import simd

/// `.sphere` — port of CoulsonPortfolioWeb `layouts/sphere.js`.
///
/// Original: files are spread over a Fibonacci sphere in path order; the radius comes from the file count and the
/// panel size so panels never touch (`R = max(18, √(n·area / 4π))`); poles are avoided (`y·0.92`); folder labels sit
/// outside the sphere along the mean direction of their files; the repo label floats above the top.
///
/// Changes for Constellate (and why):
/// - Types and extensions are cards here too, so they join the surface right after their file.
/// - **Contiguous patches.** In the original, path order only controls *latitude* (consecutive Fibonacci points are
///   137.5° apart in longitude), so a folder became a whole latitude ring and its label drifted to a pole. Here the
///   same evenly-spread point set is re-ordered along serpentine latitude bands before assignment, so a folder
///   occupies a compact patch and its hub sits right above it.
/// - **A dome, not a ball.** People stand on a floor: the sphere is squashed vertically (`sphereSquash`) and lifted so
///   its lowest card clears `floorClearance`. From inside it reads as a planetarium; from outside, as a sphere.
struct SphereLayout {
    let context: LayoutContext
    private var configuration: LayoutConfiguration { context.configuration }

    func run() -> ConstellationLayout {
        let graph = context.graph
        guard let root = graph.root else { return .empty }
        let items = context.surfaceItems()
        let n = max(items.count, 1)

        // Radius from the cards' footprint (portfolio: (PANEL_W + GAP) · (PANEL_H + GAP) per panel).
        let aspect: Float = 0.6875   // card height / width (512 × 352 texture)
        let meanWidth = items.isEmpty ? 0.3 : items.reduce(Float(0)) { $0 + 2 * context.cardRadius(for: $1) } / Float(items.count)
        let area = (meanWidth + configuration.cardGap) * (meanWidth * aspect + configuration.cardGap)
        let radius = max(configuration.minSphereRadius, (Float(n) * area / (4 * .pi)).squareRoot())
        let squash = max(0.3, min(1, configuration.sphereSquash))
        let verticalRadius = radius * squash
        let centerY = max(configuration.eyeHeight + 0.15, 0.92 * verticalRadius + configuration.floorClearance + 0.15)
        let center = SIMD3<Float>(0, centerY, 0)

        func place(_ unit: SIMD3<Float>, extra: Float = 0) -> SIMD3<Float> {
            center + SIMD3(unit.x * (radius + extra), unit.y * (verticalRadius + extra), unit.z * (radius + extra))
        }

        let points = SphereLayout.patchOrderedFibonacci(count: items.count)
        var placements: [NodeID: LayoutPlacement] = [:]
        var unitByID: [NodeID: SIMD3<Float>] = [:]
        for (item, unit) in zip(items, points) {
            let p = place(unit)
            let a = LayoutContext.azimuth(of: p, around: center)
            placements[item.id] = context.placement(item, at: p, shell: graph.depth(of: item.id), sectorStart: a, sectorEnd: a)
            unitByID[item.id] = unit
        }

        // Folder hubs: mean direction of everything below them, pushed out past the surface.
        for folder in graph.nodes where folder.kind == .folder {
            var sum = SIMD3<Float>.zero
            var count = 0
            for node in graph.subtree(of: folder.id) {
                if let u = unitByID[node.id] { sum += u; count += 1 }
            }
            guard count > 0 else { continue }
            var dir = sum / Float(count)
            if simd_length(dir) < 0.05, let first = graph.subtree(of: folder.id).lazy.compactMap({ unitByID[$0.id] }).first { dir = first }
            dir = simd_normalize(dir)
            let depthOut = 0.6 + 0.14 * Float(max(0, 4 - graph.depth(of: folder.id)))
            var p = place(dir, extra: depthOut)
            // Hubs of bottom patches would sink below the floor: slide them outward instead.
            if p.y < configuration.floorClearance {
                let flat = SIMD3<Float>(p.x - center.x, 0, p.z - center.z)
                let len = simd_length(flat)
                let outward = len > 0.01 ? flat / len : SIMD3<Float>(0, 0, -1)
                p = SIMD3(p.x, configuration.floorClearance, p.z) + outward * (configuration.floorClearance - p.y) * 0.6
            }
            let a = LayoutContext.azimuth(of: p, around: center)
            placements[folder.id] = context.placement(folder, at: p, shell: graph.depth(of: folder.id), sectorStart: a, sectorEnd: a)
        }
        // Repo label above the top (portfolio: `dirs.set('', {y: R + 7})`).
        placements[root.id] = context.placement(root, at: center + SIMD3(0, verticalRadius + 0.75, 0), shell: 0, sectorStart: 0, sectorEnd: 2 * .pi)

        return context.finish(&placements, style: .sphere, center: center, projection: LayoutStyle.sphere.timeProjection) { node in
            let a = LayoutContext.unitHash(node.id.raw) * 2 * .pi
            return place(SIMD3(cos(a), 0, -sin(a)))
        }
    }

    /// Fibonacci-sphere unit vectors (portfolio formula: `y = 1 − (i + ½)/n · 2`, `yy = 0.92·y`, golden-angle
    /// longitude) re-ordered along serpentine latitude bands so that consecutive indices are spatial neighbours.
    static func patchOrderedFibonacci(count n: Int) -> [SIMD3<Float>] {
        guard n > 0 else { return [] }
        let golden = Float.pi * (3 - Float(5).squareRoot())
        var points: [(unit: SIMD3<Float>, longitude: Float)] = []
        points.reserveCapacity(n)
        for i in 0..<n {
            let y = 1 - (Float(i) + 0.5) / Float(n) * 2
            let yy = y * 0.92
            let r = max(0, 1 - yy * yy).squareRoot()
            let theta = golden * Float(i)
            let unit = SIMD3<Float>(cos(theta) * r, yy, -sin(theta) * r)
            var lon = atan2(-unit.z, unit.x)
            if lon < 0 { lon += 2 * .pi }
            points.append((unit, lon))
        }
        // Fibonacci points are already sorted top → bottom; cut into bands and snake through them.
        let bands = max(1, Int((Float(n) / 2).squareRoot().rounded()))
        let perBand = Int((Float(n) / Float(bands)).rounded(.up))
        var ordered: [SIMD3<Float>] = []
        ordered.reserveCapacity(n)
        var start = 0
        var band = 0
        while start < n {
            let end = min(n, start + perBand)
            var slice = Array(points[start..<end])
            slice.sort { band.isMultiple(of: 2) ? $0.longitude < $1.longitude : $0.longitude > $1.longitude }
            ordered.append(contentsOf: slice.map(\.unit))
            start = end
            band += 1
        }
        return ordered
    }
}
