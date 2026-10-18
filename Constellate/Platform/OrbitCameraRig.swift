#if !os(visionOS)
import Foundation
import RealityKit
import simd

/// Virtual camera orbiting a target point for the windowed (iPad / Mac) viewport.
@MainActor
final class OrbitCameraRig {
    let camera = PerspectiveCamera()

    var yaw: Float = 0.55
    var pitch: Float = 0.22
    var distance: Float = 7.5
    /// Point the camera looks at; eased toward `desiredTarget`.
    private(set) var target: SIMD3<Float> = [0, 1.3, 0]
    var desiredTarget: SIMD3<Float> = [0, 1.3, 0]

    private var dragAnchor: (yaw: Float, pitch: Float)?
    private var magnifyAnchor: Float?
    /// While the laser pointer is active, drags must not orbit the camera.
    var isPointing = false
    private var lastPosition: SIMD3<Float> = [0, 1.3, 7.5]

    init() {
        camera.name = "OrbitCamera"
        camera.camera.fieldOfViewInDegrees = 58
        camera.camera.near = 0.02
        camera.camera.far = 120
    }

    func beginDragIfNeeded() {
        if dragAnchor == nil { dragAnchor = (yaw, pitch) }
    }

    func drag(translation: CGSize) {
        guard !isPointing else { return }
        beginDragIfNeeded()
        guard let anchor = dragAnchor else { return }
        yaw = anchor.yaw - Float(translation.width) * 0.006
        // Stay above the floor and never go fully top-down.
        pitch = min(Self.maxPitch, max(Self.minPitch, anchor.pitch + Float(translation.height) * 0.005))
    }

    func endDrag() { dragAnchor = nil }

    static let minDistance: Float = 0.8
    static let maxDistance: Float = 14
    /// One pinch can at most zoom in or out by this factor.
    static let maxGestureFactor: Float = 1.8
    static let minPitch: Float = 0.06
    static let maxPitch: Float = 1.25

    /// Pinch: logarithmic zoom relative to the distance at gesture start, clamped per gesture.
    func magnify(_ magnification: CGFloat) {
        if magnifyAnchor == nil { magnifyAnchor = distance }
        guard let startDistance = magnifyAnchor, magnification > 0 else { return }
        let factor = pow(Float(magnification), 0.45)
        let clamped = min(Self.maxGestureFactor, max(1 / Self.maxGestureFactor, factor))
        distance = Self.clampDistance(startDistance / clamped)
    }

    func endMagnify() { magnifyAnchor = nil }

    func zoom(by delta: Float) {
        distance = Self.clampDistance(distance * (1 + delta))
    }

    static func clampDistance(_ value: Float) -> Float {
        min(maxDistance, max(minDistance, value))
    }

    func frame(_ point: SIMD3<Float>) {
        desiredTarget = point
    }

    /// Follow-host: look at `point` from `distance` metres (eased by `update`).
    func flyTo(_ point: SIMD3<Float>, distance newDistance: Float) {
        desiredTarget = point
        distance = Self.clampDistance(newDistance)
    }

    /// World-space ray through a view point (origin at the camera). `point` and `viewSize` are in view coordinates.
    func ray(through point: CGPoint, viewSize: CGSize) -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
        guard viewSize.width > 1, viewSize.height > 1 else { return nil }
        let forward = simd_normalize(target - lastPosition)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        let ndcX = Float(point.x / viewSize.width) * 2 - 1
        let ndcY = 1 - Float(point.y / viewSize.height) * 2
        let tanHalf = tan(camera.camera.fieldOfViewInDegrees * .pi / 360)
        let aspect = Float(viewSize.width / viewSize.height)
        let direction = simd_normalize(forward + right * (ndcX * tanHalf * aspect) + up * (ndcY * tanHalf))
        return (lastPosition, direction)
    }

    /// Advances easing and positions the camera. Returns the viewer pose for summon placement.
    func update(deltaTime: TimeInterval) -> ViewerPose {
        let k = min(1, Float(deltaTime) * 4)
        target += (desiredTarget - target) * k
        let x = distance * cos(pitch) * sin(yaw)
        let y = distance * sin(pitch)
        let z = distance * cos(pitch) * cos(yaw)
        let position = target + SIMD3(x, y, z)
        lastPosition = position
        camera.look(at: target, from: position, relativeTo: nil)
        return ViewerPose(position: position, forward: simd_normalize(target - position))
    }
}
#endif
