#if os(visionOS)
import ConstellateKit
import RealityKit
import SwiftUI

/// Immersive constellation on visionOS: the user stands at the origin; cards billboard; gaze + pinch selects.
struct ConstellationImmersiveView: View {
    @Environment(AppModel.self) private var model

    @State private var controller = ConstellationSceneController(mode: .immersive, theme: .dark)
    @State private var headPose = HeadPoseProvider()
    @State private var updateSubscription: EventSubscription?
    @State private var dragOffset: SIMD3<Float>?
    @State private var dragStartPosition: SIMD3<Float>?
    @State private var dragReleasedDock = false

    var body: some View {
        RealityView { content in
            content.add(controller.root)
            headPose.start()
            syncAll()
            updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                tick(event.deltaTime)
            }
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in handleTap(value.entity) }
        )
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in handleDrag(value) }
                .onEnded { value in endDrag(value.entity) }
        )
        .onChange(of: model.sceneRevision) { rebuild() }
        .onChange(of: model.theme) { controller.applyTheme(model.theme) }
        .onChange(of: model.timeDial) { controller.setTimeDial(model.timeDial) }
        .onChange(of: model.selectedNodeID) { controller.setSelection(model.selectedNodeID) }
        .onChange(of: model.highlightedNodeIDs) { controller.setHighlights(model.highlightedNodeIDs) }
        .onChange(of: model.beacons) { controller.setBeacons(model.beacons, pinned: model.pinnedBeacons) }
        .onChange(of: model.pinnedBeacons) { controller.setBeacons(model.beacons, pinned: model.pinnedBeacons) }
        .onChange(of: model.summonedNodeID) { controller.setSummoned(model.summonedNodeID) }
        .onChange(of: model.dockedClusterID) { controller.setHostDocked(model.dockedClusterID) }
        .onChange(of: model.participants) { controller.setParticipants(model.participants, hideLocal: true) }
        .onChange(of: model.pins) { controller.setPins(model.pins) }
        .onChange(of: model.pointers) { controller.setPointers(model.pointers) }
        .onAppear { model.immersiveState = .open }
        .onDisappear {
            model.immersiveState = .closed
            headPose.stop()
            updateSubscription = nil
        }
    }

    private func syncAll() {
        rebuild()
        controller.setParticipants(model.participants, hideLocal: true)
        controller.setBeacons(model.beacons, pinned: model.pinnedBeacons)
        controller.setHostDocked(model.dockedClusterID)
    }

    private func rebuild() {
        controller.rebuild(graph: model.graph, layout: model.layout, clusters: model.clusters, theme: model.theme, timeDial: model.timeDial, projectRoot: model.projectRootURL)
        controller.setSelection(model.selectedNodeID)
        controller.setHighlights(model.highlightedNodeIDs)
        controller.setPins(model.pins)
    }

    private func tick(_ deltaTime: TimeInterval) {
        if let pose = headPose.pose() { controller.viewerPose = pose } else { controller.viewerPose = .standing }
        controller.setHostPresence(model.hostPresence)
        controller.update(deltaTime: deltaTime)
        if !controller.expiredBeacons.isEmpty { model.removeBeacons(controller.expiredBeacons) }
    }

    private func handleTap(_ entity: Entity) {
        if let nodeID = controller.nodeID(for: entity) {
            model.select(nodeID)
        } else if let clusterID = controller.clusterID(for: entity) {
            model.toggleDock(clusterID)
        } else if controller.isHostOrb(entity) {
            controller.returnHostToViewer()
        }
    }

    /// Host orb: free drag. Docked cluster orb: pull > 0.25 m to release the host.
    private func handleDrag(_ value: EntityTargetValue<DragGesture.Value>) {
        let location = value.convert(value.location3D, from: .local, to: .scene)
        if controller.isHostOrb(value.entity) {
            if dragOffset == nil {
                dragOffset = controller.hostOrb.basePosition - location
                controller.hostOrb.isDragging = true
            }
            controller.hostOrb.setBaseFromDrag(location + (dragOffset ?? .zero))
        } else if let clusterID = controller.clusterID(for: value.entity), let orb = controller.clusterOrbs[clusterID] {
            if dragStartPosition == nil {
                dragStartPosition = orb.basePosition
                dragOffset = orb.basePosition - location
                orb.isDragging = true
                dragReleasedDock = false
            }
            let pulled = location + (dragOffset ?? .zero)
            orb.setBaseFromDrag(pulled)
            if let start = dragStartPosition, !dragReleasedDock, model.dockedClusterID == clusterID, simd_distance(pulled, start) > 0.25 {
                dragReleasedDock = true
                model.undockHost()
            }
        }
    }

    private func endDrag(_ entity: Entity) {
        if controller.isHostOrb(entity) {
            controller.hostOrb.isDragging = false
        } else if let clusterID = controller.clusterID(for: entity), let orb = controller.clusterOrbs[clusterID] {
            orb.isDragging = false
            if let start = dragStartPosition { orb.summon(to: start) }
        }
        dragOffset = nil
        dragStartPosition = nil
        dragReleasedDock = false
    }
}
#endif
