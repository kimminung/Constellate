#if !os(visionOS)
import ConstellateKit
import RealityKit
import SwiftUI

/// Windowed constellation (iPad / Mac): RealityView + orbit camera + entity-targeted taps + laser pointer.
struct ConstellationViewport: View {
    @Environment(AppModel.self) private var model

    @State private var controller = ConstellationSceneController(mode: .windowed, theme: .dark)
    @State private var rig = OrbitCameraRig()
    @State private var updateSubscription: EventSubscription?
    @State private var viewSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            RealityView { content in
                content.camera = .virtual
                content.add(controller.root)
                content.add(rig.camera)
                syncAll()
                updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    tick(event.deltaTime)
                }
            }
            .gesture(
                SpatialTapGesture()
                    .targetedToAnyEntity()
                    .onEnded { value in handleTap(value.entity) }
            )
            // Long-press (0.35 s) then drag = laser pointer.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { value in
                        guard case .second(true, let drag) = value else { return }
                        rig.isPointing = true
                        if let drag { point(at: drag.location) }
                    }
                    .onEnded { _ in endPointing() }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in rig.drag(translation: value.translation) }
                    .onEnded { _ in rig.endDrag() }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in rig.magnify(value.magnification) }
                    .onEnded { _ in rig.endMagnify() }
            )
            .onChange(of: geometry.size, initial: true) { viewSize = geometry.size }
        }
        .background(model.theme.skyTop.swiftUIColor)
#if os(macOS)
        .overlay {
            ScrollWheelMonitor { notches in
                // One notch ≈ 4 % of the distance; scrolling up brings the camera closer.
                rig.zoom(by: Float(-notches) * 0.04)
            }
        }
#endif
        .onChange(of: model.sceneRevision) { rebuild() }
        .onChange(of: model.theme) { controller.applyTheme(model.theme) }
        .onChange(of: model.timeDial) { controller.setTimeDial(model.timeDial) }
        .onChange(of: model.selectedNodeID) {
            controller.setSelection(model.selectedNodeID)
            if let id = model.selectedNodeID, let p = model.layout.position3(for: id, timeDial: model.timeDial) {
                rig.frame(p)
            }
        }
        .onChange(of: model.followEventToken) {
            // Follow-host: fly to the summoned / toured node.
            if let id = model.guideTargetID, let p = model.layout.position3(for: id, timeDial: model.timeDial) {
                rig.flyTo(p, distance: 3.5)
            }
        }
        .onChange(of: model.highlightedNodeIDs) { controller.setHighlights(model.highlightedNodeIDs) }
        .onChange(of: model.relationRevision) { controller.setRelationOptions(mode: model.relationMode, hidden: model.hiddenRelations) }
        .onChange(of: model.beacons) { controller.setBeacons(model.beacons, pinned: model.pinnedBeacons) }
        .onChange(of: model.pinnedBeacons) { controller.setBeacons(model.beacons, pinned: model.pinnedBeacons) }
        .onChange(of: model.summonedNodeID) { controller.setSummoned(model.summonedNodeID) }
        .onChange(of: model.dockedClusterID) { controller.setHostDocked(model.dockedClusterID) }
        .onChange(of: model.participants) { controller.setParticipants(model.participants, hideLocal: false) }
        .onChange(of: model.pins) { controller.setPins(model.pins) }
        .onChange(of: model.pointers) { controller.setPointers(model.pointers) }
        .onDisappear { updateSubscription = nil }
        .overlay(alignment: .topTrailing) {
            if model.isIngesting {
                ProgressView(model.ingestProgress.map { L("파일 \($0.filesParsed)개…", "\($0.filesParsed) files…") } ?? L("프로젝트 읽는 중…", "Reading project…"))
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if rig.isPointing {
                Label(L("포인터", "Pointer"), systemImage: "scope")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.trailing, 16)
                    .padding(.bottom, 150)
            }
        }
    }

    private func syncAll() {
        rebuild()
        controller.setParticipants(model.participants, hideLocal: false)
        controller.setBeacons(model.beacons, pinned: model.pinnedBeacons)
        controller.setHostDocked(model.dockedClusterID)
    }

    private func rebuild() {
        controller.setRelationOptions(mode: model.relationMode, hidden: model.hiddenRelations)
        controller.rebuild(graph: model.graph, layout: model.layout, clusters: model.clusters, theme: model.theme, timeDial: model.timeDial,
                           projectRoot: model.projectRootURL, insights: model.insights)
        controller.setSelection(model.selectedNodeID)
        controller.setHighlights(model.highlightedNodeIDs)
        controller.setPins(model.pins)
        // Frame the whole structure: every layout style has its own extent and centre (a wall, a dome, a helix…).
        let sphere = model.layout.boundingSphere
        rig.distance = OrbitCameraRig.clampDistance(max(4, sphere.radius * 1.45))
        rig.frame([sphere.center.x, min(max(sphere.center.y, 1.0), 2.4), sphere.center.z])
    }

    private func tick(_ deltaTime: TimeInterval) {
        let pose = rig.update(deltaTime: deltaTime)
        controller.viewerPose = pose
        controller.setHostPresence(model.hostPresence)
        controller.update(deltaTime: deltaTime)
        if !controller.expiredBeacons.isEmpty {
            model.removeBeacons(controller.expiredBeacons)
        }
    }

    private func handleTap(_ entity: Entity) {
        if let nodeID = controller.nodeID(for: entity) {
            model.select(nodeID)
        } else if let clusterID = controller.clusterID(for: entity) {
            model.toggleDock(clusterID)
        } else if controller.isHostOrb(entity) {
            model.undockHost()
            controller.returnHostToViewer()
        }
    }

    // MARK: - Laser pointer

    /// Projects a camera ray through the touch point; uses a scene hit when there is one, else a plane
    /// facing the camera at the selected node's (or orbit target's) depth.
    private func point(at location: CGPoint) {
        guard let ray = rig.ray(through: location, viewSize: viewSize) else { return }
        let hit: SIMD3<Float>
        if let sceneHit = controller.raycastHit(origin: ray.origin, direction: ray.direction) {
            hit = sceneHit
        } else {
            let anchor = model.selectedNodeID.flatMap { model.layout.position3(for: $0, timeDial: model.timeDial) } ?? rig.target
            let normal = -simd_normalize(rig.target - ray.origin)
            let denominator = simd_dot(ray.direction, normal)
            guard abs(denominator) > 0.0001 else { return }
            let t = simd_dot(anchor - ray.origin, normal) / denominator
            guard t > 0.1 else { return }
            hit = ray.origin + ray.direction * t
        }
        controller.setLocalPointer(origin: ray.origin + ray.direction * 0.4 - [0, 0.15, 0], hit: hit)
        model.setLocalPointer(hit)
    }

    private func endPointing() {
        rig.isPointing = false
        rig.endDrag()
        controller.clearLocalPointer()
        model.setLocalPointer(nil)
    }
}
#endif
