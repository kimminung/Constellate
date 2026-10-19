import ConstellateKit
import Foundation
import RealityKit
import SwiftUI
import simd

/// Shared meshes (one allocation each) and small geometry builders.
@MainActor
enum MeshFactory {

    /// Unit card: 1 m wide, 0.6875 m tall (matches the 512×352 texture), facing +Z.
    static let unitCard: MeshResource = .generatePlane(width: 1, height: Float(TextureFactory.cardHeight) / Float(TextureFactory.cardWidth), cornerRadius: 0.04)
    static let unitFrame: MeshResource = .generatePlane(width: 1.07, height: Float(TextureFactory.cardHeight) / Float(TextureFactory.cardWidth) + 0.07, cornerRadius: 0.06)
    static let unitSphere: MeshResource = .generateSphere(radius: 1)
    static let pinSphere: MeshResource = .generateSphere(radius: 0.035)
    /// Card-sized quad for `FX_CardGlow`: the card plus 0.08 on every side (Blender: `CARD_GLOW_MARGIN`).
    static let unitCardGlow: MeshResource = .generatePlane(width: 1.16, height: Float(TextureFactory.cardHeight) / Float(TextureFactory.cardWidth) + 0.16)
    /// 1 m quad facing +Z for sprites (particles, ripples); scale it to size.
    static let spriteQuad: MeshResource = .generatePlane(width: 1, height: 1)
    /// Particle stand-in when the sprite textures are missing.
    static let particleSphere: MeshResource = .generateSphere(radius: 0.16)

    private static var ringCache: [String: MeshResource] = [:]

    /// Flat ring (annulus) lying in the XY plane, extruded `depth` along Z. Rotate −90° about X to lay it flat.
    static func ring(radius: Float, width: Float, depth: Float = 0.003) -> MeshResource {
        let key = "\(radius)-\(width)-\(depth)"
        if let cached = ringCache[key] { return cached }
        let outer = CGFloat(radius + width / 2)
        let inner = CGFloat(max(0.0005, radius - width / 2))
        var path = Path()
        path.addEllipse(in: CGRect(x: -outer, y: -outer, width: outer * 2, height: outer * 2))
        path.addEllipse(in: CGRect(x: -inner, y: -inner, width: inner * 2, height: inner * 2))
        var options = MeshResource.ShapeExtrusionOptions()
        options.extrusionMethod = .linear(depth: depth)
        options.chamferRadius = 0
        let mesh: MeshResource
        do {
            mesh = try MeshResource(extruding: path, extrusionOptions: options)
        } catch {
            print("[MeshFactory] ring extrusion failed: \(error)")
            mesh = .generateBox(size: SIMD3(radius * 2, depth, radius * 2))
        }
        ringCache[key] = mesh
        return mesh
    }

    /// Builds a mesh from precomputed line geometry (see `LineGeometry`).
    static func mesh(from geometry: LineGeometry, name: String) -> MeshResource? {
        guard !geometry.positions.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(geometry.positions)
        descriptor.normals = MeshBuffers.Normals(geometry.normals)
        descriptor.primitives = .triangles(geometry.indices)
        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            print("[MeshFactory] line mesh failed: \(error)")
            return nil
        }
    }

    /// Relation tubes and arrowheads from the Kit's `TubeMesh`. `uv.x` runs 0 → 1 along each edge in flow
    /// direction, so the `FX_EdgeRamp` texture brightens every edge toward its target.
    static func mesh(from tube: TubeMesh, name: String) -> MeshResource? {
        guard !tube.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(tube.positions)
        descriptor.normals = MeshBuffers.Normals(tube.normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(tube.uvs)
        descriptor.primitives = .triangles(tube.indices)
        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            print("[MeshFactory] tube mesh failed: \(error)")
            return nil
        }
    }

    /// Centred 3-D text label.
    static func label(_ text: String, size: Float) -> MeshResource {
        .generateText(text, extrusionDepth: size * 0.04, font: .systemFont(ofSize: CGFloat(size)), containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
    }
}

/// Thin-box line geometry, built on any thread.
nonisolated struct LineGeometry: Sendable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    var segmentCount = 0

    /// Appends a rectangular prism from `a` to `b` with the given thickness (4 side faces, no caps).
    mutating func addSegment(from a: SIMD3<Float>, to b: SIMD3<Float>, thickness: Float) {
        let d = b - a
        let len = simd_length(d)
        guard len > 0.0005 else { return }
        let dir = d / len
        let helper: SIMD3<Float> = abs(dir.y) < 0.98 ? [0, 1, 0] : [1, 0, 0]
        let u = simd_normalize(simd_cross(dir, helper)) * (thickness / 2)
        let v = simd_normalize(simd_cross(dir, u)) * (thickness / 2)
        let base = UInt32(positions.count)
        let corners: [SIMD3<Float>] = [a + u + v, a - u + v, a - u - v, a + u - v, b + u + v, b - u + v, b - u - v, b + u - v]
        positions.append(contentsOf: corners)
        let n = simd_normalize(u + v)
        normals.append(contentsOf: Array(repeating: n, count: 8))
        // side faces: (0,1,5,4) (1,2,6,5) (2,3,7,6) (3,0,4,7)
        let quads: [(UInt32, UInt32, UInt32, UInt32)] = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        for q in quads {
            indices.append(contentsOf: [base + q.0, base + q.1, base + q.2, base + q.0, base + q.2, base + q.3])
            indices.append(contentsOf: [base + q.0, base + q.2, base + q.1, base + q.0, base + q.3, base + q.2])
        }
        segmentCount += 1
    }

    /// Dashed line made of short segments.
    mutating func addDashed(from a: SIMD3<Float>, to b: SIMD3<Float>, dash: Float, gap: Float, thickness: Float) {
        let d = b - a
        let len = simd_length(d)
        guard len > 0.001 else { return }
        let dir = d / len
        var t: Float = 0
        while t < len {
            let end = min(len, t + dash)
            addSegment(from: a + dir * t, to: a + dir * end, thickness: thickness)
            t += dash + gap
        }
    }
}
