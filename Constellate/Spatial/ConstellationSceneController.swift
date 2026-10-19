import ConstellateKit
import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Where the viewer is, in scene space. Head pose on visionOS; the orbit camera on iPad/Mac.
struct ViewerPose: Equatable {
    var position: SIMD3<Float>
    var forward: SIMD3<Float>

    static let standing = ViewerPose(position: [0, 1.4, 0], forward: [0, 0, -1])

    /// Point `distance` metres ahead (horizontal forward), lowered slightly for comfort.
    func ahead(_ distance: Float, drop: Float = 0.1) -> SIMD3<Float> {
        var f = forward
        f.y = 0
        f = simd_length(f) > 0.001 ? simd_normalize(f) : [0, 0, -1]
        return position + f * distance - [0, drop, 0]
    }
}

/// Owns the RealityKit entity tree for one constellation and mutates it from `AppModel` state.
///
/// root
/// ├─ Environment (sky, floor, stage ring)
/// ├─ Nodes (CodeNodeEntity per spatial node, each with its role star)
/// ├─ Edges (EdgeRenderer: one tube mesh per relation × emphasis, flow particles)
/// ├─ Orbs (cluster orbs) + Host (host orb)
/// ├─ Beacons
/// ├─ Avatars
/// └─ Summon (duplicate card + dashed guide)
@MainActor
final class ConstellationSceneController {

    enum Mode { case immersive, windowed }

    static let maxNodeEntities = 2500
    static let maxBespokeTextures = 400
    static let maxClusterOrbs = 120
    /// Star glyphs are extra entities; above this many cards only hubs and the most depended-on files get one.
    static let maxStars = 1200

    let mode: Mode
    let root = Entity()
    let environment = EnvironmentEntity()
    let nodesRoot = Entity()
    let edgesRoot = Entity()
    let orbsRoot = Entity()
    let beaconsRoot = Entity()
    let avatarsRoot = Entity()
    let summonRoot = Entity()
    let hostOrb: OrbEntity

    private(set) var theme: ConstellateTheme
    private(set) var graph: CodeGraph?
    private(set) var layout: ConstellationLayout = .empty
    private(set) var clusters: [CodeCluster] = []
    private(set) var timeDial: Float = 0
    private var projectRoot: URL?

    private(set) var nodeEntities: [NodeID: CodeNodeEntity] = [:]
    private(set) var clusterOrbs: [String: OrbEntity] = [:]
    /// Relations (built lazily so it can parent itself under `edgesRoot`).
    private lazy var edgeRenderer = EdgeRenderer(root: edgesRoot)
    private let starFactory = NodeStarFactory()
    private var insights: GraphInsights?
    /// What the relation layer shows (mirrors `AppModel.relationMode` / `hiddenRelations`).
    private(set) var relationMode: RelationDisplayMode = .all
    private(set) var hiddenRelations: Set<RelationKind> = []
    /// Nodes touching the focus through a drawn relation (empty = nothing dims).
    private(set) var relatedNodes: Set<NodeID> = []
    private var beacons: [NodeID: BeaconEntity] = [:]
    private var avatars: [ParticipantID: AvatarEntity] = [:]
    private var pointerEntities: [ParticipantID: ModelEntity] = [:]
    private var genericMaterials: [ArchitectureLayer: UnlitMaterial] = [:]
    private var summonCard: Entity?
    private var summonGuide: ModelEntity?
    private var summonedNodeID: NodeID?

    private var buildTask: Task<Void, Never>?
    private var textureTask: Task<Void, Never>?
    private var edgeTask: Task<Void, Never>?
    private var dialTask: Task<Void, Never>?
    private var pendingDial: Float?
    private var lastDialApplied: Float = 0

    private var selectedNodeID: NodeID?
    private var highlighted: Set<NodeID> = []
    /// Open review pins per node (kept so a rebuild can re-apply them to the new cards).
    private var pinCounts: [NodeID: Int] = [:]
    private var dockedClusterID: String?
    private var hostFlight: Flight?
    private var faceClock: Float = 0
    private var hostDecor: Entity?
    private var clusterDecor: Entity?
    private var beaconDecor: Entity?
    private var pinDecor: Entity?
    private var bustDecor: Entity?
    private var pointerDecor: Entity?

    private var localPointerDart: ModelEntity?
    private var localPointerRay: ModelEntity?
    private var guideArrow: ModelEntity?
    private var guideTarget: SIMD3<Float>?
    private var guideAge: Float = 0

    /// Updated by the hosting view (head pose or camera) — used for summon and undock placement.
    var viewerPose: ViewerPose = .standing

    private struct Flight {
        var from: SIMD3<Float>
        var to: SIMD3<Float>
        var elapsed: Float = 0
        let duration: Float = 0.6
        var docking: Bool
        var clusterID: String
    }

    init(mode: Mode, theme: ConstellateTheme) {
        self.mode = mode
        self.theme = theme
        hostOrb = OrbEntity(style: .host, coreRadius: 0.052, accent: theme.orbHalo, bandColors: theme.orbBands, name: "HostOrb")
        root.name = "ConstellationRoot"
        for (child, name) in [(environment.root, "Environment"), (edgesRoot, "Edges"), (nodesRoot, "Nodes"), (orbsRoot, "Orbs"), (beaconsRoot, "Beacons"), (avatarsRoot, "Avatars"), (summonRoot, "Summon")] {
            child.name = name
            root.addChild(child)
        }
        root.addChild(hostOrb.root)
        hostOrb.place(at: ViewerPose.standing.ahead(0.9))
        Task { await loadDecor() }
    }

    private func loadDecor() async {
        // Sky and floor first: they frame everything else and should never wait on decor, sprites or glyphs.
        let builtTheme = theme
        await environment.build(theme: builtTheme)
        // The view's first `rebuild(…)` usually delivers the model's theme while the sky is still loading.
        if theme != builtTheme { await environment.apply(theme: theme) }
        hostDecor = await AssetLoader.entity(named: "HostOrb")
        clusterDecor = await AssetLoader.entity(named: "ClusterOrb")
        beaconDecor = await AssetLoader.entity(named: "Beacon")
        pinDecor = await AssetLoader.entity(named: "ReviewPin")
        bustDecor = await AssetLoader.entity(named: "Avatar_Bust")
        pointerDecor = await AssetLoader.entity(named: "Pointer_Dart")
        if let hostDecor { hostOrb.attachDecor(hostDecor) }
        await FXTextures.preload()
        await starFactory.load()
        // Sprites, glyphs and the pin asset may arrive after the first build: refresh what used fallbacks.
        if graph != nil {
            refreshStars()
            rebuildEdges()
            refreshEmphasis()
            applyPinCounts()
        }
    }

    // MARK: - Build

    func rebuild(graph: CodeGraph, layout: ConstellationLayout, clusters: [CodeCluster], theme: ConstellateTheme, timeDial: Float, projectRoot: URL?,
                 insights: GraphInsights? = nil) {
        buildTask?.cancel()
        textureTask?.cancel()
        edgeTask?.cancel()
        self.graph = graph
        self.layout = layout
        self.insights = insights
        self.clusters = clusters
        if theme != self.theme {
            // The controller starts on `.dark`; a view's first rebuild brings the model's theme.
            Task { await environment.apply(theme: theme) }
            hostOrb.applyAccent(theme.orbHalo, bands: theme.orbBands)
        }
        self.theme = theme
        self.timeDial = timeDial
        self.lastDialApplied = timeDial
        self.projectRoot = projectRoot
        buildTask = Task { await performBuild() }
    }

    /// Replaces every card and orb. Views push selection / highlights / pins right after `rebuild(…)` — while the
    /// *old* cards still exist — so everything the controller remembers is re-applied to the new cards at the end.
    /// The summoned copy in front of the viewer is kept (only its guide line moves) unless its node is gone.
    private func performBuild() async {
        guard let graph else { return }
        nodesRoot.children.removeAll()
        orbsRoot.children.removeAll()
        edgeRenderer.removeAll()
        if let id = summonedNodeID, graph.node(id) == nil { clearSummon() }
        nodeEntities.removeAll()
        clusterOrbs.removeAll()
        relatedNodes = []

        // 1. Node cards (generic material first; bespoke textures stream in).
        let spatial = graph.nodes
            .filter { $0.kind.isSpatial && layout.placements[$0.id] != nil }
            .sorted { lhs, rhs in
                let a = layout.placements[lhs.id]?.shell ?? 0, b = layout.placements[rhs.id]?.shell ?? 0
                return a != b ? a < b : lhs.name < rhs.name
            }
            .prefix(Self.maxNodeEntities)
        let materials = await makeGenericMaterials()
        // A newer rebuild started while the materials rendered: it owns the scene now (no duplicate cards).
        if Task.isCancelled { return }
        genericMaterials = materials
        for node in spatial {
            guard let placement = layout.placements[node.id] else { continue }
            let material = genericMaterials[node.layer] ?? UnlitMaterial(color: theme.code.cardBackground.platformColor)
            let entity = CodeNodeEntity(nodeID: node.id, radius: placement.radius, material: material, highlightColor: theme.highlight)
            entity.root.position = layout.project(placement, timeDial: timeDial)
            nodesRoot.addChild(entity.root)
            nodeEntities[node.id] = entity
        }
        refreshStars()
        faceCards(force: true)

        // 2. Cluster orbs.
        let shown = clusters.sorted { $0.totalLines > $1.totalLines }.prefix(Self.maxClusterOrbs)
        for cluster in shown {
            guard let centroid = layout.centroid(of: cluster.memberNodeIDs, timeDial: timeDial) else { continue }
            let layerColor = theme.color(for: cluster.dominantLayer)
            let orb = OrbEntity(style: .cluster, coreRadius: 0.078, accent: layerColor, bandColors: Self.clusterBands(layerColor), name: "cluster:" + cluster.id)
            orb.place(at: centroid + [0, 0.05, 0])
            orb.setLabel(cluster.title, color: theme.code.plain)
            if let clusterDecor, let clone = clusterDecor.clone(recursive: true) as Entity? { orb.attachDecor(clone) }
            orbsRoot.addChild(orb.root)
            clusterOrbs[cluster.id] = orb
        }
        if let dockedClusterID { applyDockVisuals(clusterID: dockedClusterID, docked: true, animated: false) }

        // 3. Re-apply view state to the new cards: selection / highlights, pins, beacons and the summon guide
        //    (new layout positions).
        refreshEmphasis()
        applyPinCounts()
        repositionBeacons()
        if let id = summonedNodeID, let origin = layout.position3(for: id, timeDial: timeDial) { updateSummonGuide(origin: origin) }
        if let selectedNodeID { ensureTexture(for: selectedNodeID) }

        // 4. Edges + textures stream in.
        rebuildEdges()
        streamTextures(for: Array(spatial.prefix(Self.maxBespokeTextures)))
    }

    private static func clusterBands(_ c: RGBA) -> [RGBA] {
        [c, c.shiftedHue(by: 40), c.shiftedHue(by: -40), .white]
    }

    /// One generic card material per architecture layer (rendered off the main actor).
    private func makeGenericMaterials() async -> [ArchitectureLayer: UnlitMaterial] {
        let palette = theme.code
        let bands = ArchitectureLayer.allCases.map { ($0, theme.color(for: $0)) }
        let images = await Task.detached(priority: .userInitiated) {
            bands.map { layer, band in (layer, TextureFactory.genericCardImage(kindLabel: layer.rawValue.capitalized, palette: palette, band: band)) }
        }.value
        var materials: [ArchitectureLayer: UnlitMaterial] = [:]
        for (layer, image) in images {
            guard let image, let texture = await AssetLoader.texture(image) else { continue }
            materials[layer] = Self.cardMaterial(texture)
        }
        return materials
    }

    private static func cardMaterial(_ texture: TextureResource) -> UnlitMaterial {
        var m = UnlitMaterial()
        m.color = .init(tint: RGBA.white.platformColor, texture: .init(texture))
        m.blending = .transparent(opacity: .init(floatLiteral: 0.94))
        return m
    }

    /// Renders bespoke card textures in small batches on a background task and applies them on the main actor.
    private func streamTextures(for nodes: [CodeNode]) {
        guard let graph else { return }
        let palette = theme.code
        let projectRoot = self.projectRoot
        let theme = self.theme
        let insights = self.insights
        textureTask = Task { [weak self] in
            for chunk in stride(from: 0, to: nodes.count, by: 24).map({ Array(nodes[$0..<min($0 + 24, nodes.count)]) }) {
                if Task.isCancelled { return }
                let rendered: [(NodeID, SendableImage)] = await Task.detached(priority: .utility) {
                    chunk.compactMap { node in
                        let source = SourceProvider.source(for: node, in: graph, projectRoot: projectRoot)
                        let lines = SourceProvider.previewLines(source, count: 9)
                        return TextureFactory.cardImage(title: node.name, subtitle: CardContent.subtitle(for: node, insights: insights), lines: lines,
                                                        palette: palette, band: theme.color(for: node.layer), chip: CardContent.chip(for: node)).map { (node.id, $0) }
                    }
                }.value
                for (id, image) in rendered {
                    guard let self, !Task.isCancelled else { return }
                    guard self.nodeEntities[id] != nil, let texture = await AssetLoader.texture(image) else { continue }
                    self.applyBespoke(Self.cardMaterial(texture), to: id)
                }
                await Task.yield()
            }
        }
    }

    /// Loads one card's texture on demand (tap on a generic card).
    func ensureTexture(for id: NodeID) {
        guard let graph, let node = graph.node(id), let entity = nodeEntities[id], !entity.hasBespokeTexture else { return }
        let palette = theme.code, band = theme.color(for: node.layer), projectRoot = self.projectRoot, insights = self.insights
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                let source = SourceProvider.source(for: node, in: graph, projectRoot: projectRoot)
                return TextureFactory.cardImage(title: node.name, subtitle: CardContent.subtitle(for: node, insights: insights),
                                                lines: SourceProvider.previewLines(source, count: 9), palette: palette, band: band, chip: CardContent.chip(for: node))
            }.value
            guard let self, let image, let texture = await AssetLoader.texture(image) else { return }
            self.applyBespoke(Self.cardMaterial(texture), to: id)
        }
    }

    /// Puts a rendered code texture on the card — and on its summoned copy, which was cloned with whatever
    /// material the card had at that moment (often the generic one, e.g. right after a rebuild).
    private func applyBespoke(_ material: UnlitMaterial, to id: NodeID) {
        guard let entity = nodeEntities[id] else { return }
        entity.setMaterial(material, bespoke: true)
        if summonedNodeID == id, let copy = summonCard?.children.first(where: { $0.name == entity.card.name }) as? ModelEntity {
            copy.model?.materials = [material]
        }
    }

    /// Relations for the current graph / layout / dial / focus / relation options (built off the main actor).
    private func rebuildEdges() {
        edgeTask?.cancel()   // a debounced rebuild still waiting is covered by this one
        guard let graph else { return }
        var options = EdgeSceneOptions()
        options.mode = relationMode
        options.hidden = hiddenRelations
        options.focus = selectedNodeID.map { Set([$0]) } ?? []
        // Immersive: the viewer stands inside the structure, so arcs bulge inward, toward them (portfolio rule).
        options.bulgeInward = mode == .immersive
        options.timeDial = timeDial
        options.reduceMotion = Self.reduceMotion
        options.insights = insights
        edgeRenderer.rebuild(graph: graph, layout: layout, options: options, theme: theme) { [weak self] scene in
            self?.applyFocus(scene)
        }
    }

    private func applyFocus(_ scene: EdgeScene) {
        relatedNodes = scene.related
        refreshDimming()
        applyCycleHalos()
    }

    /// Focus dimming (portfolio): with a selection and relations on, cards outside the related set (the selection,
    /// its contents and everything a drawn focus edge touches) recede. Highlighted cards never dim — host answers,
    /// a remote `.highlight` or the Inspector's cycle button must stay readable.
    private func refreshDimming() {
        let dim = relationMode != .off && !relatedNodes.isEmpty
        for (id, entity) in nodeEntities {
            entity.setDimmed(dim && !relatedNodes.contains(id) && !highlighted.contains(id))
        }
    }

    /// Coalesces bursts of relation rebuilds (dial scrubbing, clicking through cards) into one build.
    private func scheduleEdgeRebuild(after milliseconds: Int) {
        edgeTask?.cancel()
        edgeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard let self, !Task.isCancelled else { return }
            self.rebuildEdges()
        }
    }

    /// Relation layer options from the model (mode = off / focus / all, legend toggles).
    func setRelationOptions(mode newMode: RelationDisplayMode, hidden: Set<RelationKind>) {
        guard newMode != relationMode || hidden != hiddenRelations else { return }
        relationMode = newMode
        hiddenRelations = hidden
        rebuildEdges()
    }

    /// Draw counts per kind (`drawn / total`) of the relations currently on screen.
    var relationCounts: (drawn: [RelationKind: Int], total: [RelationKind: Int]) {
        (edgeRenderer.scene.drawnCounts, edgeRenderer.scene.totalCounts)
    }

    private static var reduceMotion: Bool {
#if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
#elseif canImport(AppKit)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
#else
        false
#endif
    }

    // MARK: - Stars

    /// One role star per card (`StarEncoder`): shape = role, colour = layer, size = fan-in, glow = recency.
    /// Very large graphs keep the draw-call budget: hubs first, then the most depended-on files (`maxStars`).
    private func refreshStars() {
        guard let graph else { return }
        var ranked: [(id: NodeID, node: CodeNode, fanIn: Int)] = []
        ranked.reserveCapacity(nodeEntities.count)
        for id in nodeEntities.keys {
            guard let node = graph.node(id) else { continue }
            ranked.append((id, node, insights?.fanIn(of: id) ?? 0))
        }
        if ranked.count > Self.maxStars {
            ranked.sort { a, b in
                let hubA = a.node.kind == .module || a.node.kind == .folder, hubB = b.node.kind == .module || b.node.kind == .folder
                if hubA != hubB { return hubA }
                if a.fanIn != b.fanIn { return a.fanIn > b.fanIn }
                return a.id.raw < b.id.raw
            }
        }
        for (index, item) in ranked.enumerated() {
            guard let entity = nodeEntities[item.id], let placement = layout.placements[item.id] else { continue }
            guard index < Self.maxStars else {
                entity.setStar(nil, appearance: nil)
                continue
            }
            let appearance = StarEncoder.appearance(for: item.node, theme: theme, fanIn: item.fanIn,
                                                    recency: placement.position4.w, inCycle: false)
            entity.setStar(starFactory.makeStar(appearance), appearance: appearance)
        }
        applyCycleHalos()
    }

    /// Halo stars of every file in the selected node's dependency cycle (cycles are diagnosed on demand — they are
    /// common inside one Swift module, so painting all of them would be noise).
    private func applyCycleHalos() {
        var wanted: Set<NodeID> = []
        if let selectedNodeID, let insights {
            let members = Set(insights.cycleMembers(of: selectedNodeID))
            if !members.isEmpty {
                for id in nodeEntities.keys where insights.file(of: id).map({ members.contains($0) }) == true { wanted.insert(id) }
            }
        }
        for (id, entity) in nodeEntities {
            let want = wanted.contains(id)
            if want && !entity.hasHalo {
                entity.setHalo(starFactory.makeHalo(color: EdgeBatchKey.cycleColor))
            } else if !want && entity.hasHalo {
                entity.setHalo(nil)
            }
        }
    }

    // MARK: - Time dial

    /// Throttled: nodes glide to their new projection; edges rebuild once the dial settles.
    func setTimeDial(_ dial: Float) {
        timeDial = dial
        pendingDial = dial
        guard dialTask == nil else { return }
        dialTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self else { return }
            self.dialTask = nil
            guard let dial = self.pendingDial else { return }
            self.pendingDial = nil
            self.applyDial(dial)
        }
    }

    private func applyDial(_ dial: Float) {
        guard abs(dial - lastDialApplied) > 0.002 else { return }
        lastDialApplied = dial
        for (id, entity) in nodeEntities {
            guard let placement = layout.placements[id] else { continue }
            let target = layout.project(placement, timeDial: dial)
            entity.root.move(to: Transform(scale: entity.root.scale, rotation: entity.root.orientation, translation: target), relativeTo: nodesRoot, duration: 0.35, timingFunction: .easeInOut)
        }
        for cluster in clusters {
            guard let orb = clusterOrbs[cluster.id], let centroid = layout.centroid(of: cluster.memberNodeIDs, timeDial: dial) else { continue }
            orb.summon(to: centroid + [0, 0.05, 0])
        }
        if let summonedNodeID, let pos = layout.position3(for: summonedNodeID, timeDial: dial) { updateSummonGuide(origin: pos) }
        repositionBeacons(dial: dial, animated: true)
        scheduleEdgeRebuild(after: 250)
    }

    // MARK: - Theme

    /// Re-tints materials in place; cards keep the fixed code palette.
    func applyTheme(_ theme: ConstellateTheme) {
        self.theme = theme
        Task { await environment.apply(theme: theme) }
        edgeRenderer.applyTheme(theme)
        refreshStars()
        hostOrb.applyAccent(theme.orbHalo, bands: theme.orbBands)
        for cluster in clusters {
            guard let orb = clusterOrbs[cluster.id] else { continue }
            if cluster.id == dockedClusterID {
                orb.applyAccent(theme.orbHalo, bands: theme.orbBands)
            } else {
                let c = theme.color(for: cluster.dominantLayer)
                orb.applyAccent(c, bands: Self.clusterBands(c))
            }
        }
        for beacon in beacons.values { beacon.setColor(theme.beacon) }
        for (id, avatar) in avatars {
            avatar.setAccent(theme.avatarAccent.shiftedHue(by: avatar.participant.hueOffset))
            _ = id
        }
        refreshEmphasis()
    }

    // MARK: - Selection / highlight

    func setSelection(_ id: NodeID?) {
        let changed = id != selectedNodeID
        selectedNodeID = id
        if let id {
            ensureTexture(for: id)
            nodeEntities[id]?.setDimmed(false)   // don't wait for the relation rebuild to light the new focus
        }
        refreshEmphasis()
        // Focus changes which relations are emphasised (or drawn at all, in focus mode). Debounced, so clicking
        // through cards rebuilds the relation meshes once, for the card the user stops on.
        if changed { scheduleEdgeRebuild(after: 60) }
    }

    func setHighlights(_ ids: Set<NodeID>) {
        highlighted = ids
        refreshEmphasis()
        refreshDimming()
    }

    private func refreshEmphasis() {
        for (id, entity) in nodeEntities {
            let emphasis: CodeNodeEntity.Emphasis = id == selectedNodeID ? .selected : highlighted.contains(id) ? .highlighted : .none
            entity.setEmphasis(emphasis, highlight: theme.highlight, selection: theme.code.plain)
        }
    }

    func setPins(_ pins: [ReviewPin]) {
        var counts: [NodeID: Int] = [:]
        for pin in pins where !pin.resolved { counts[pin.nodeID, default: 0] += 1 }
        pinCounts = counts
        applyPinCounts()
    }

    private func applyPinCounts() {
        for (id, entity) in nodeEntities {
            entity.setPins(pinCounts[id] ?? 0, color: theme.beacon, decor: pinDecor)
        }
    }

    // MARK: - Beacons

    func setBeacons(_ ids: [NodeID], pinned: Set<NodeID>) {
        let wanted = Set(ids)
        for (id, beacon) in beacons where !wanted.contains(id) {
            beacon.root.removeFromParent()
            beacons[id] = nil
        }
        for id in ids {
            guard let position = layout.position3(for: id, timeDial: timeDial) else { continue }
            if let existing = beacons[id] {
                existing.isPinned = pinned.contains(id)
                existing.root.position = [position.x, 0, position.z]
                continue
            }
            let beacon = BeaconEntity(nodeID: id, color: theme.beacon, decor: beaconDecor?.clone(recursive: true))
            beacon.isPinned = pinned.contains(id)
            beacon.root.position = [position.x, 0, position.z]
            beaconsRoot.addChild(beacon.root)
            beacons[id] = beacon
        }
    }

    /// Beacons stand on the floor under their node: follow it when a new layout or the time dial moves it.
    private func repositionBeacons(dial: Float? = nil, animated: Bool = false) {
        for (id, beacon) in beacons {
            guard let p = layout.position3(for: id, timeDial: dial ?? timeDial) else { continue }
            let target: SIMD3<Float> = [p.x, 0, p.z]
            if animated {
                beacon.root.move(to: Transform(translation: target), relativeTo: beaconsRoot, duration: 0.35, timingFunction: .easeInOut)
            } else {
                beacon.root.position = target
            }
        }
    }

    /// Ids of beacons that aged out this frame (the model removes them).
    private(set) var expiredBeacons: [NodeID] = []

    // MARK: - Summon

    func setSummoned(_ id: NodeID?) {
        guard id != summonedNodeID else { return }
        clearSummon()
        guard let id, let source = nodeEntities[id], let origin = layout.position3(for: id, timeDial: timeDial) else { return }
        summonedNodeID = id
        ensureTexture(for: id)
        let clone = source.root.clone(recursive: true)
        clone.name = "summon:" + id.raw
        clone.components.remove(InputTargetComponent.self)
        clone.components.remove(OpacityComponent.self)   // never summon a dimmed copy
        clone.position = origin
        summonRoot.addChild(clone)
        summonCard = clone
        let target = viewerPose.ahead(0.6, drop: 0.08)
        let width: Float = 0.42
        let yaw = atan2(viewerPose.position.x - target.x, viewerPose.position.z - target.z)
        clone.move(to: Transform(scale: SIMD3(repeating: width), rotation: simd_quatf(angle: yaw, axis: [0, 1, 0]), translation: target), relativeTo: summonRoot, duration: 0.6, timingFunction: .easeOut)
        updateSummonGuide(origin: origin, destination: target)
    }

    private func updateSummonGuide(origin: SIMD3<Float>, destination: SIMD3<Float>? = nil) {
        summonGuide?.removeFromParent()
        let dest = destination ?? summonCard?.position ?? origin
        var geometry = LineGeometry()
        geometry.addDashed(from: origin, to: dest, dash: 0.07, gap: 0.05, thickness: 0.006)
        guard let mesh = MeshFactory.mesh(from: geometry, name: "summon-guide") else { return }
        var material = UnlitMaterial(color: theme.beacon.platformColor)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.8))
        material.faceCulling = .none
        let guide = ModelEntity(mesh: mesh, materials: [material])
        guide.name = "SummonGuide"
        summonRoot.addChild(guide)
        summonGuide = guide
    }

    private func clearSummon() {
        summonCard?.removeFromParent()
        summonGuide?.removeFromParent()
        summonCard = nil
        summonGuide = nil
        summonedNodeID = nil
    }

    // MARK: - Host orb

    func setHostPresence(_ presence: OrbEntity.Presence) {
        hostOrb.presence = presence
        if let dockedClusterID, let orb = clusterOrbs[dockedClusterID] { orb.presence = presence }
    }

    /// Where the free host orb rests: 0.9 m ahead of the viewer.
    func hostRestPosition() -> SIMD3<Float> { viewerPose.ahead(0.9, drop: 0.12) }

    func returnHostToViewer() {
        guard dockedClusterID == nil, hostFlight == nil else { return }
        hostOrb.summon(to: hostRestPosition())
    }

    func setHostDocked(_ clusterID: String?) {
        if let clusterID {
            guard clusterID != dockedClusterID else { return }
            if let previous = dockedClusterID { applyDockVisuals(clusterID: previous, docked: false, animated: false) }
            dockedClusterID = clusterID
            guard let orb = clusterOrbs[clusterID] else {
                applyDockVisuals(clusterID: clusterID, docked: true, animated: false)
                return
            }
            hostOrb.root.isEnabled = true
            hostFlight = Flight(from: hostOrb.root.position, to: orb.root.position, docking: true, clusterID: clusterID)
        } else {
            guard let previous = dockedClusterID else { return }
            dockedClusterID = nil
            let start = clusterOrbs[previous]?.root.position ?? hostOrb.root.position
            hostOrb.root.isEnabled = true
            hostOrb.place(at: start)
            hostOrb.root.scale = SIMD3(repeating: 0.2)
            applyDockVisuals(clusterID: previous, docked: false, animated: true)
            hostFlight = Flight(from: start, to: hostRestPosition(), docking: false, clusterID: previous)
        }
    }

    private func applyDockVisuals(clusterID: String, docked: Bool, animated: Bool) {
        guard let orb = clusterOrbs[clusterID], let cluster = clusters.first(where: { $0.id == clusterID }) else { return }
        if docked {
            orb.applyAccent(theme.orbHalo, bands: theme.orbBands)
            if !animated {
                hostOrb.root.isEnabled = false
            }
        } else {
            let c = theme.color(for: cluster.dominantLayer)
            orb.applyAccent(c, bands: Self.clusterBands(c))
            orb.presence = .idle
        }
    }

    // MARK: - Participants

    func setParticipants(_ participants: [Participant], hideLocal: Bool) {
        let wanted = Set(participants.map(\.id))
        for (id, avatar) in avatars where !wanted.contains(id) {
            avatar.root.removeFromParent()
            avatars[id] = nil
        }
        for (index, participant) in participants.enumerated() {
            let accent = theme.avatarAccent.shiftedHue(by: participant.hueOffset)
            let avatar: AvatarEntity
            if let existing = avatars[participant.id] {
                avatar = existing
            } else {
                avatar = AvatarEntity(participant: participant, accent: accent, bust: bustDecor?.clone(recursive: true))
                avatarsRoot.addChild(avatar.root)
                avatars[participant.id] = avatar
            }
            let seat = AvatarEntity.seatTransform(index: index)
            avatar.root.position = seat.position
            avatar.root.orientation = simd_quatf(angle: seat.yaw, axis: [0, 1, 0])
            avatar.root.isEnabled = !(hideLocal && participant.isLocal)
        }
    }

    func setPointers(_ pointers: [ParticipantID: SIMD3<Float>]) {
        for (id, entity) in pointerEntities where pointers[id] == nil {
            entity.removeFromParent()
            pointerEntities[id] = nil
        }
        for (id, position) in pointers {
            if let existing = pointerEntities[id] {
                existing.position = position
                continue
            }
            let accent = theme.avatarAccent.shiftedHue(by: avatars[id]?.participant.hueOffset ?? 0)
            let dart = makePointerDart(accent: accent)
            dart.name = "pointer:" + id.raw
            dart.position = position
            avatarsRoot.addChild(dart)
            pointerEntities[id] = dart
        }
    }

    // MARK: - Laser pointer

    /// Nearest collision hit along a ray (cards, orbs, avatars). Ignores the sky dome.
    func raycastHit(origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float = 30) -> SIMD3<Float>? {
        guard let scene = root.scene else { return nil }
        let hits = scene.raycast(origin: origin, direction: direction, length: maxDistance, query: .all, mask: .all, relativeTo: nil)
        return hits
            .filter { $0.entity !== environment.dome && $0.distance > 0.05 }
            .min { $0.distance < $1.distance }?
            .position
    }

    /// Shows the local participant's laser: a dart at `hit` and a thin ray from `origin`.
    func setLocalPointer(origin: SIMD3<Float>, hit: SIMD3<Float>) {
        let accent = theme.avatarAccent
        if localPointerDart == nil {
            let dart = makePointerDart(accent: accent)
            dart.name = "pointer:local"
            avatarsRoot.addChild(dart)
            localPointerDart = dart
            var material = UnlitMaterial(color: accent.lightened(0.3).platformColor)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.55))
            let ray = ModelEntity(mesh: .generateBox(size: 1), materials: [material])
            ray.name = "pointer:ray"
            avatarsRoot.addChild(ray)
            localPointerRay = ray
        }
        localPointerDart?.position = hit
        guard let ray = localPointerRay else { return }
        let delta = hit - origin
        let length = simd_length(delta)
        guard length > 0.01 else { return }
        ray.position = origin + delta / 2
        ray.orientation = simd_quatf(from: [0, 0, 1], to: delta / length)
        ray.scale = [0.004, 0.004, length]
    }

    func clearLocalPointer() {
        localPointerDart?.removeFromParent()
        localPointerRay?.removeFromParent()
        localPointerDart = nil
        localPointerRay = nil
    }

    private func makePointerDart(accent: RGBA) -> ModelEntity {
        var material = UnlitMaterial(color: accent.platformColor)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.95))
        let dart = ModelEntity(mesh: MeshFactory.pinSphere, materials: [material])
        if let decor = pointerDecor?.clone(recursive: true) {
            AssetLoader.fit(decor, to: 0.05)
            AssetLoader.retintAccent(in: decor, color: accent)
            dart.addChild(decor)
            dart.model = nil
        }
        return dart
    }

    // MARK: - Follow-host guide

    /// Glowing arrow floating 0.7 m ahead of the viewer, pointing at `position`. Nil hides it.
    func setGuideTarget(_ position: SIMD3<Float>?) {
        guideTarget = position
        guideAge = 0
        guard position != nil else {
            guideArrow?.isEnabled = false
            return
        }
        if guideArrow == nil {
            var material = UnlitMaterial(color: theme.highlight.platformColor)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.9))
            let arrow = ModelEntity(mesh: .generateCone(height: 0.12, radius: 0.035), materials: [material])
            arrow.name = "GuideArrow"
            root.addChild(arrow)
            guideArrow = arrow
        }
        guideArrow?.isEnabled = true
    }

    private func updateGuide(dt: Float) {
        guard let target = guideTarget, let arrow = guideArrow, arrow.isEnabled else { return }
        guideAge += dt
        let anchor = viewerPose.ahead(0.7, drop: 0.15)
        arrow.position = anchor
        let toTarget = target - anchor
        let distance = simd_length(toTarget)
        if distance > 0.01 {
            arrow.orientation = simd_quatf(from: [0, 1, 0], to: toTarget / distance)
        }
        let pulse = 1 + sin(guideAge * 5) * 0.12
        arrow.scale = SIMD3(repeating: pulse)
        // Auto-hide after 8 s or once the viewer is close to the target.
        if guideAge > 8 || simd_distance(viewerPose.position, target) < 1.0 {
            arrow.isEnabled = false
        }
    }

    // MARK: - Hit testing

    func nodeID(for entity: Entity) -> NodeID? { CodeNodeEntity.nodeID(for: entity) }

    func clusterID(for entity: Entity) -> String? {
        var current: Entity? = entity
        while let e = current {
            if e.name.hasPrefix("cluster:") { return String(e.name.dropFirst("cluster:".count)) }
            current = e.parent
        }
        return nil
    }

    func isHostOrb(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let e = current {
            if e === hostOrb.root { return true }
            current = e.parent
        }
        return false
    }

    // MARK: - Frame update

    func update(deltaTime: TimeInterval) {
        let dt = Float(deltaTime)
        hostOrb.update(deltaTime: deltaTime)
        edgeRenderer.update(deltaTime: dt, viewer: viewerPose.position, faceViewer: mode == .windowed)
        for orb in clusterOrbs.values { orb.update(deltaTime: deltaTime) }

        if var flight = hostFlight {
            flight.elapsed += dt
            let p = min(1, flight.elapsed / flight.duration)
            let eased = p * p * (3 - 2 * p)
            let position = flight.from + (flight.to - flight.from) * eased
            hostOrb.place(at: position)
            let scale: Float = flight.docking ? 1 - eased * 0.85 : 0.2 + eased * 0.8
            hostOrb.root.scale = SIMD3(repeating: scale)
            if p >= 1 {
                hostFlight = nil
                if flight.docking {
                    hostOrb.root.isEnabled = false
                    hostOrb.root.scale = SIMD3(repeating: 1)
                    clusterOrbs[flight.clusterID]?.presence = hostOrb.presence
                } else {
                    hostOrb.root.scale = SIMD3(repeating: 1)
                }
            } else {
                hostFlight = flight
            }
        }

        updateGuide(dt: dt)

        expiredBeacons.removeAll(keepingCapacity: true)
        for (id, beacon) in beacons {
            beacon.update(deltaTime: deltaTime)
            if beacon.isExpired { expiredBeacons.append(id) }
        }

        if mode == .windowed {
            faceClock += dt
            if faceClock > 0.2 {
                faceClock = 0
                faceCards(force: false)
            }
        }
    }

    /// Windowed mode has no BillboardComponent: yaw cards and labels toward the viewer every 0.2 s.
    private func faceCards(force: Bool) {
        guard mode == .windowed || force else { return }
        let viewer = viewerPose.position
        for entity in nodeEntities.values {
            let p = entity.root.position
            entity.root.orientation = simd_quatf(angle: atan2(viewer.x - p.x, viewer.z - p.z), axis: [0, 1, 0])
        }
        for orb in clusterOrbs.values {
            guard let pivot = orb.labelPivot else { continue }
            let p = orb.root.position
            pivot.orientation = simd_quatf(angle: atan2(viewer.x - p.x, viewer.z - p.z), axis: [0, 1, 0])
        }
        for avatar in avatars.values {
            guard let pivot = avatar.labelPivot else { continue }
            let p = avatar.root.position
            // Counter the avatar's own yaw so the label faces the viewer.
            let world = atan2(viewer.x - p.x, viewer.z - p.z)
            let own = atan2(avatar.root.orientation.act([0, 0, 1]).x, avatar.root.orientation.act([0, 0, 1]).z)
            pivot.orientation = simd_quatf(angle: world - own, axis: [0, 1, 0])
        }
    }
}

/// Card header text shared by the streamed and on-demand card textures (runs off the main actor).
nonisolated enum CardContent {
    /// "file · ui · 132 lines · in 3 / out 5" — coupling of the node's file (GraphInsights Ca / Ce).
    static func subtitle(for node: CodeNode, insights: GraphInsights?) -> String {
        var parts = [node.kind.rawValue, node.layer.rawValue, "\(node.lineCount) lines"]
        if let insights, node.kind == .file || node.kind == .type || node.kind == .extensionDecl {
            let fanIn = insights.fanIn(of: node.id), fanOut = insights.fanOut(of: node.id)
            if fanIn + fanOut > 0 { parts.append("in \(fanIn) / out \(fanOut)") }
        }
        return parts.joined(separator: " · ")
    }

    /// Role chip ("View", "Model" …) in the role colour; nil for folders and unclassified files.
    static func chip(for node: CodeNode) -> TextureFactory.Chip? {
        guard let role = node.role, !role.style.label.isEmpty else { return nil }
        return TextureFactory.Chip(label: role.style.label, color: role.style.color)
    }
}
