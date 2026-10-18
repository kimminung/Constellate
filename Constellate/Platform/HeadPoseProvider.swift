#if os(visionOS)
import ARKit
import QuartzCore
import RealityKit
import simd

/// Head pose via ARKit `WorldTrackingProvider` (device only; the simulator reports unsupported → fixed pose).
@MainActor
final class HeadPoseProvider {
    private let session = ARKitSession()
    private var worldTracking: WorldTrackingProvider?
    private var runTask: Task<Void, Never>?
    private(set) var isRunning = false

    func start() {
        guard runTask == nil, WorldTrackingProvider.isSupported else { return }
        let provider = WorldTrackingProvider()
        worldTracking = provider
        runTask = Task { [weak self] in
            do {
                try await self?.session.run([provider])
                self?.isRunning = true
            } catch {
                print("[HeadPose] \(error)")
            }
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        session.stop()
        isRunning = false
    }

    /// Current head pose or nil when not tracked.
    func pose() -> ViewerPose? {
        guard let worldTracking, worldTracking.state == .running,
              let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked else { return nil }
        let m = anchor.originFromAnchorTransform
        let position = SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        let forward = -SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        return ViewerPose(position: position, forward: simd_normalize(forward))
    }
}
#endif
