import ConstellateKit
import Foundation
import RealityKit
import simd

/// Stylised bust marker for a meeting participant: `Avatar_Bust.usdz` if present, else capsule + head sphere,
/// always with a name plate ring and a floating name in the participant's accent.
@MainActor
final class AvatarEntity {
    static let seatRadius: Float = 1.2
    static let seatCount = 6

    let root = Entity()
    let participant: Participant
    private let ring: ModelEntity
    private var nameLabel: ModelEntity?
    private var body: ModelEntity?
    private var head: ModelEntity?

    init(participant: Participant, accent: RGBA, bust: Entity?) {
        self.participant = participant
        root.name = "avatar:" + participant.id.raw

        var ringMaterial = UnlitMaterial(color: accent.platformColor)
        ringMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        ring = ModelEntity(mesh: MeshFactory.ring(radius: 0.22, width: 0.025), materials: [ringMaterial])
        ring.name = "NamePlate"
        ring.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        ring.position = [0, 0.012, 0]
        root.addChild(ring)

        if let bust {
            AssetLoader.fit(bust, to: 0.45)
            bust.name = "Bust"
            root.addChild(bust)
        } else {
            var bodyMaterial = PhysicallyBasedMaterial()
            bodyMaterial.baseColor = .init(tint: RGBA(hex: 0x1C2238).platformColor)
            bodyMaterial.roughness = 0.6
            bodyMaterial.metallic = 0.1
            let body = ModelEntity(mesh: .generateCylinder(height: 0.26, radius: 0.13), materials: [bodyMaterial])
            body.name = "Body"
            body.position = [0, 0.13, 0]
            root.addChild(body)
            self.body = body

            var headMaterial = PhysicallyBasedMaterial()
            headMaterial.baseColor = .init(tint: RGBA(hex: 0x2A3150).platformColor)
            headMaterial.emissiveColor = .init(color: accent.platformColor)
            headMaterial.emissiveIntensity = 0.35
            headMaterial.roughness = 0.4
            let head = ModelEntity(mesh: MeshFactory.unitSphere, materials: [headMaterial])
            head.name = "Head"
            head.scale = SIMD3(repeating: 0.095)
            head.position = [0, 0.37, 0]
            root.addChild(head)
            self.head = head
        }
        setName(participant.displayName + (participant.role == .host ? " · host" : ""), color: accent)
    }

    func setName(_ text: String, color: RGBA) {
        nameLabel?.removeFromParent()
        let mesh = MeshFactory.label(text, size: 0.045)
        var material = UnlitMaterial(color: color.lightened(0.3).platformColor)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.95))
        let label = ModelEntity(mesh: mesh, materials: [material])
        label.name = "Name"
        label.position = [-mesh.bounds.extents.x / 2, 0.5, 0]
        let pivot = Entity()
        pivot.name = "LabelPivot"
        pivot.addChild(label)
#if os(visionOS)
        pivot.components.set(BillboardComponent())
#endif
        root.addChild(pivot)
        nameLabel = label
    }

    var labelPivot: Entity? { nameLabel?.parent }

    func setAccent(_ accent: RGBA) {
        var ringMaterial = UnlitMaterial(color: accent.platformColor)
        ringMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        ring.model?.materials = [ringMaterial]
        if let head {
            var headMaterial = PhysicallyBasedMaterial()
            headMaterial.baseColor = .init(tint: RGBA(hex: 0x2A3150).platformColor)
            headMaterial.emissiveColor = .init(color: accent.platformColor)
            headMaterial.emissiveIntensity = 0.35
            head.model?.materials = [headMaterial]
        }
        setName(participant.displayName + (participant.role == .host ? " · host" : ""), color: accent)
    }

    /// Seat `index` on the stage ring, facing the origin.
    static func seatTransform(index: Int) -> (position: SIMD3<Float>, yaw: Float) {
        // Seat 0 is behind the user (+Z) so remote members appear around, not in front of the local viewer's code.
        let angle = Float(index) / Float(seatCount) * 2 * .pi + .pi
        let position = SIMD3<Float>(sin(angle) * seatRadius, 0, cos(angle) * seatRadius)
        // Face the origin: forward (+Z of the bust) should point toward −position.
        let yaw = atan2(-position.x, -position.z)
        return (position, yaw)
    }
}
