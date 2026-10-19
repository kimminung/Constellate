import ConstellateKit
import Foundation
import Observation
import simd

/// Single source of truth for the app. Every scene (dashboard window, inspector windows, immersive space,
/// RealityView viewports) reads from here; the scene controllers mirror this state into RealityKit.
@Observable
@MainActor
final class AppModel {

    enum HostState: Equatable {
        case free
        case docked(clusterID: String)
        case thinking
        case speaking
    }

    enum HostActivity: Equatable { case idle, listening, thinking, speaking }

    enum ImmersiveState: Equatable { case closed, inTransition, open }

    struct TranscriptEntry: Identifiable, Hashable {
        enum Role: Hashable { case user, host, system }
        let id = UUID()
        var role: Role
        var text: String
        var nodeIDs: [NodeID] = []
        var date: Date = .now
    }

    // MARK: Graph

    private(set) var graph: CodeGraph
    private(set) var layout: ConstellationLayout
    /// File-level dependency analysis (fan-in/out, cycles, impact) for the inspector, stars and cycle highlights.
    private(set) var insights: GraphInsights
    /// Relation edges per kind in the whole graph (legend counts).
    private(set) var relationTotals: [RelationKind: Int] = [:]
    private(set) var clusters: [CodeCluster] = []
    private(set) var granularity: ClusterGranularity = .file
    /// Bumped whenever graph/layout/clusters are replaced so viewports rebuild the entity tree.
    private(set) var sceneRevision = 0
    private(set) var projectRootURL: URL?
    private(set) var ingestProgress: IngestProgress?
    private(set) var isIngesting = false
    var statusMessage: String?

    // MARK: Visual state

    private(set) var theme: ConstellateTheme = .dark
    private(set) var timeDial: Float = 0
    /// Shape of the constellation (persisted). Changing it re-lays out the graph and rebuilds the scene.
    private(set) var layoutStyle: LayoutStyle
    /// Which relations are drawn — off / focus (selection only) / all — the portfolio's `L` cycle (persisted).
    private(set) var relationMode: RelationDisplayMode
    /// Relation kinds switched off in the legend (persisted).
    private(set) var hiddenRelations: Set<RelationKind>
    /// Bumped when `relationMode` / `hiddenRelations` change so viewports push them to their controllers.
    private(set) var relationRevision = 0
    var selectedNodeID: NodeID?
    var highlightedNodeIDs: Set<NodeID> = []
    private(set) var beacons: [NodeID] = []
    private(set) var pinnedBeacons: Set<NodeID> = []
    private(set) var summonedNodeID: NodeID?
    var pointers: [ParticipantID: SIMD3<Float>] = [:]
    /// Local laser pointer hit position (rendered by the scene controller, broadcast at ≤ 10 Hz).
    private(set) var localPointer: SIMD3<Float>?
    private var lastPointerSend: ContinuousClock.Instant = .now
    /// Incremented when a remote summon / tour step should move this member's view (follow-host).
    private(set) var followEventToken = 0
    private(set) var guideTargetID: NodeID?

    // MARK: Host

    private(set) var hostActivity: HostActivity = .idle
    private(set) var dockedClusterID: String?
    private(set) var hostTranscript: [TranscriptEntry] = []

    var hostState: HostState {
        switch hostActivity {
        case .thinking: return .thinking
        case .speaking: return .speaking
        case .idle, .listening:
            if let dockedClusterID { return .docked(clusterID: dockedClusterID) }
            return .free
        }
    }

    /// Visual energy for the orbs: thinking > speaking > listening > idle.
    var hostPresence: OrbEntity.Presence {
        if hostAI.isThinking || hostActivity == .thinking { return .thinking }
        if hostActivity == .speaking { return .speaking }
        if speech.state == .listening { return .listening }
        return .idle
    }

    var dockedCluster: CodeCluster? { clusters.first { $0.id == dockedClusterID } }

    var hostStateLabel: String {
        switch hostState {
        case .free: L("호스트 오브 · 자유", "Host orb · free")
        case .docked(let id): L("\(clusters.first { $0.id == id }?.title ?? id)에 도킹됨", "Docked in \(clusters.first { $0.id == id }?.title ?? id)")
        case .thinking: L("생각 중…", "Thinking…")
        case .speaking: L("말하는 중", "Speaking")
        }
    }

    // MARK: Meeting

    var participants: [Participant]
    private(set) var localParticipant: Participant
    private(set) var pins: [ReviewPin] = []
    private(set) var tour: LearningTour?
    private(set) var currentStep = 0
    var followHost = true
    private(set) var meetingMode: MeetingMode = .analysis

    // MARK: UI

    var immersiveState: ImmersiveState = .closed
    /// Transient banner shown over the viewport (auto-clears after 2 s).
    private(set) var toast: String?
    private var toastTask: Task<Void, Never>?
    var showProjectImporter = false
    /// Incremented by ⌘F so the navigator focuses its search field.
    var searchFocusToken = 0
    /// Read replies aloud (persisted).
    var speakReplies: Bool {
        didSet {
            UserDefaults.standard.set(speakReplies, forKey: "speakReplies")
            if !speakReplies { hostVoice.stop() }
        }
    }
    /// Hides transient chrome (placeholders, toasts) for clean screenshots (persisted).
    var screenshotMode: Bool {
        didSet { UserDefaults.standard.set(screenshotMode, forKey: "screenshotMode") }
    }
    /// Host AI, speech and interface language (persisted in `LanguageSetting`). Korean by default; English is an
    /// advanced option in Settings. Change it through `setLanguage` so the AI session and recognizer follow.
    var language: HostLanguage { LanguageSetting.shared.language }

    // MARK: Services

    let hostAI = HostAI()
    let hostVoice = HostVoice()
    let speech = SpeechListener()
    let session = SessionCoordinator()
    private let router = VoiceCommandRouter()
    private var speakingTask: Task<Void, Never>?
    private var accessedURL: URL?
    /// Generation counters for background work. A result is applied only when no newer request — or a newer
    /// graph — arrived while it was computing; otherwise a slow layout of the previous project could land on the
    /// new one (placements that match no node = an empty sky).
    private var installGeneration = 0
    private var layoutGeneration = 0
    private var clusterGeneration = 0

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        speakReplies = defaults.object(forKey: "speakReplies") == nil ? true : defaults.bool(forKey: "speakReplies")
        screenshotMode = defaults.bool(forKey: "screenshotMode")
        let style = defaults.string(forKey: AppModel.layoutStyleKey).flatMap(LayoutStyle.init(rawValue:)) ?? .appDefault
        layoutStyle = style
        relationMode = defaults.string(forKey: AppModel.relationModeKey).flatMap(RelationDisplayMode.init(rawValue:)) ?? .all
        hiddenRelations = Set((defaults.stringArray(forKey: AppModel.hiddenRelationsKey) ?? []).compactMap(RelationKind.init(rawValue:)))
        let sample = SampleGraph.orbitNotes()
        graph = sample
        layout = ConstellationLayoutEngine(style: style).layout(sample)
        insights = GraphInsights(graph: sample)
        relationTotals = AppModel.countRelations(sample)
        let local = Participant(id: .local(), displayName: Self.deviceUserName(), role: .host, hueOffset: 0, isLocal: true)
        localParticipant = local
        participants = [local]
        clusters = ClusterBuilder().clusters(from: sample, granularity: granularity)
        hostAI.context.model = self
        session.model = self
        speech.onFinalUtterance = { [weak self] text in
            Task { await self?.handleVoice(text) }
        }
        speech.onWakeWord = { [weak self] in
            self?.hostActivity = .listening
        }
        hostVoice.onStart = { [weak self] in
            self?.speakingTask?.cancel()
            self?.hostActivity = .speaking
        }
        hostVoice.onFinish = { [weak self] in
            guard let self, self.hostActivity == .speaking else { return }
            self.hostActivity = .idle
        }
        hostAI.language = language
        speech.language = language
        hostAI.prewarm()
        hostTranscript.append(TranscriptEntry(role: .system, text: L("호스트 준비 완료 · ", "Host ready · ") + hostAI.backendLabel))
    }

    private static let layoutStyleKey = "layoutStyle"
    private static let relationModeKey = "relationMode"
    private static let hiddenRelationsKey = "hiddenRelations"

    private static func deviceUserName() -> String {
#if os(macOS)
        let name = ProcessInfo.processInfo.fullUserName
        return name.isEmpty ? LanguageSetting.shared.language.pick("나", "You") : name
#else
        return LanguageSetting.shared.language.pick("나", "You")
#endif
    }

    // MARK: - Project

    func loadSample() {
        releaseProjectAccess()
        let token = beginInstall()
        Task { await install(graph: SampleGraph.orbitNotes(), projectRoot: nil, token: token) }
    }

    /// Opens a folder picked by the user. Keeps security-scoped access alive so cards can read source later.
    func openProject(url: URL) async {
        guard !isIngesting else { return }
        releaseProjectAccess()
        let token = beginInstall()
        let accessing = url.startAccessingSecurityScopedResource()
        if accessing { accessedURL = url }
        isIngesting = true
        ingestProgress = nil
        statusMessage = L("\(url.lastPathComponent) 읽는 중…", "Reading \(url.lastPathComponent)…")
        do {
            let ingested = try await ProjectIngestor().ingest(rootURL: url) { [weak self] progress in
                guard progress.filesSeen % 20 == 0 else { return }
                // Re-capture weakly: the outer closure runs off the main actor, so it must not share its `self` var.
                Task { @MainActor [weak self] in self?.ingestProgress = progress }
            }
            if await install(graph: ingested, projectRoot: url, token: token) {
                statusMessage = L("\(ingested.projectName): 파일 \(ingested.fileCount)개, \(ingested.totalLines)줄",
                                  "\(ingested.projectName): \(ingested.fileCount) files, \(ingested.totalLines) lines")
            }
        } catch {
            // Superseded (the sample was loaded meanwhile, which also ended this folder's access): stay quiet.
            if token == installGeneration { statusMessage = error.localizedDescription }
        }
        isIngesting = false
        ingestProgress = nil
    }

    /// Every project request (open / sample) takes a token; only the newest request is ever installed.
    private func beginInstall() -> Int {
        installGeneration += 1
        return installGeneration
    }

    private func releaseProjectAccess() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    /// Lays out, clusters and analyses `newGraph` off the main actor, then swaps it in. Returns false (and changes
    /// nothing) when a newer project request arrived meanwhile — the newer one wins.
    @discardableResult
    private func install(graph newGraph: CodeGraph, projectRoot: URL?, token: Int) async -> Bool {
        let gran = granularity
        let style = layoutStyle
        let (newLayout, newClusters, newInsights) = await Task.detached(priority: .userInitiated) {
            (ConstellationLayoutEngine(style: style).layout(newGraph), ClusterBuilder().clusters(from: newGraph, granularity: gran), GraphInsights(graph: newGraph))
        }.value
        guard token == installGeneration else { return false }
        // Relayouts / reclusters still computing were started for the previous graph: drop them.
        layoutGeneration += 1
        clusterGeneration += 1
        graph = newGraph
        layout = newLayout
        insights = newInsights
        relationTotals = Self.countRelations(newGraph)
        clusters = newClusters
        stats = newGraph.stats()
        projectRootURL = projectRoot
        selectedNodeID = nil
        highlightedNodeIDs = []
        beacons = []
        pinnedBeacons = []
        summonedNodeID = nil
        dockedClusterID = nil
        tour = nil
        pins = []
        sceneRevision += 1
        // The layout style or cluster granularity may have changed while this graph was being laid out.
        if style != layoutStyle { relayout() }
        if gran != granularity { recluster() }
        if session.isHost {
            session.send(.graphDigest(projectName: newGraph.projectName, nodeCount: newGraph.nodes.count, checksum: GraphDigest.checksum(newGraph)))
        }
        return true
    }

    /// Recomputes the layout for the current graph and style; only the newest request is applied.
    func relayout() {
        layoutGeneration += 1
        let token = layoutGeneration, g = graph, style = layoutStyle
        Task {
            let newLayout = await Task.detached(priority: .userInitiated) { ConstellationLayoutEngine(style: style).layout(g) }.value
            // A newer style request — or a new graph — landed while this one was computing.
            guard token == layoutGeneration else { return }
            layout = newLayout
            sceneRevision += 1
        }
    }

    // MARK: - Layout style / relations

    func setLayoutStyle(_ style: LayoutStyle, broadcast: Bool = true) {
        guard style != layoutStyle else { return }
        layoutStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: Self.layoutStyleKey)
        relayout()
        if broadcast && session.isHost { session.send(.layoutStyle(style)) }
    }

    func setRelationMode(_ mode: RelationDisplayMode, broadcast: Bool = true) {
        guard mode != relationMode else { return }
        relationMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.relationModeKey)
        relationRevision += 1
        if broadcast && session.isHost { session.send(.relationMode(mode)) }
    }

    /// off → focus → all → off (the portfolio's `L` key).
    func cycleRelationMode() {
        setRelationMode(relationMode.next)
        showToast(L("관계: ", "Relations: ") + relationMode.name(language))
    }

    /// Legend toggle for one relation kind (local: each participant filters their own view).
    func toggleRelation(_ kind: RelationKind) {
        if hiddenRelations.contains(kind) { hiddenRelations.remove(kind) } else { hiddenRelations.insert(kind) }
        UserDefaults.standard.set(hiddenRelations.map(\.rawValue).sorted(), forKey: Self.hiddenRelationsKey)
        relationRevision += 1
    }

    func showAllRelations() {
        guard !hiddenRelations.isEmpty else { return }
        hiddenRelations = []
        UserDefaults.standard.set([String](), forKey: Self.hiddenRelationsKey)
        relationRevision += 1
    }

    /// Relation edges per kind in the whole graph (legend counts).
    private static func countRelations(_ graph: CodeGraph) -> [RelationKind: Int] {
        var counts: [RelationKind: Int] = [:]
        for e in graph.edges { if let rel = e.semantic { counts[rel, default: 0] += 1 } }
        return counts
    }

    /// Coupling numbers for the inspector (Martin metrics on the node's file).
    func metrics(for id: NodeID) -> NodeMetrics { insights.metrics(for: id) }

    /// The node's relations grouped by kind and direction (members folded into it).
    func relationGroups(for id: NodeID) -> [RelationGroup] { RelationDigest.groups(for: id, in: graph) }

    /// One-paragraph digest for the host's prompt: role, coupling, cycle and the most informative relations — the
    /// same facts the constellation encodes visually, so the host can talk about what the person is looking at.
    func relationSummary(for id: NodeID) -> String {
        guard let node = graph.node(id) else { return "" }
        var parts: [String] = []
        let lang = language
        if let role = node.role, !role.style.label.isEmpty {
            parts.append(lang.pick("역할은 \(role.style.label)입니다.", "Its role is \(role.style.label)."))
        }
        let m = insights.metrics(for: id)
        if m.fanIn + m.fanOut > 0 {
            parts.append(lang.pick("이 파일에 의존하는 파일 \(m.fanIn)개, 이 파일이 의존하는 파일 \(m.fanOut)개.",
                                   "\(m.fanIn) files depend on its file and it depends on \(m.fanOut)."))
        }
        if m.cycleIndex != nil { parts.append(lang.pick("이 파일은 순환 의존에 속합니다.", "Its file is part of a dependency cycle.")) }
        let informative = relationGroups(for: id).filter { $0.relation != .uses && $0.relation != .imports }.prefix(5)
        for group in informative {
            let names = group.nodes.prefix(4).compactMap { graph.node($0)?.name }.joined(separator: ", ")
            parts.append("\(group.relation.style.name(lang)) \(group.outgoing ? "→" : "←") \(names)\(group.total > 4 ? " (+\(group.total - 4))" : "").")
        }
        return parts.joined(separator: " ")
    }

    func setGranularity(_ value: ClusterGranularity) {
        guard value != granularity else { return }
        granularity = value
        recluster()
    }

    /// Rebuilds the cluster orbs for the current graph and granularity; only the newest request is applied.
    private func recluster() {
        clusterGeneration += 1
        let token = clusterGeneration, g = graph, value = granularity
        Task {
            let newClusters = await Task.detached(priority: .userInitiated) { ClusterBuilder().clusters(from: g, granularity: value) }.value
            guard token == clusterGeneration else { return }
            clusters = newClusters
            dockedClusterID = nil
            sceneRevision += 1
        }
    }

    // MARK: - Theme / dial / mode

    func setTheme(_ newTheme: ConstellateTheme, broadcast: Bool = true) {
        guard newTheme != theme else { return }
        theme = newTheme
        if broadcast && session.isHost { session.send(.theme(newTheme)) }
    }

    func setTimeDial(_ value: Float, broadcast: Bool = true) {
        let clamped = max(-1, min(1, value))
        guard clamped != timeDial else { return }
        timeDial = clamped
        if broadcast && session.isHost { session.send(.timeDial(clamped)) }
    }

    func setMeetingMode(_ mode: MeetingMode, broadcast: Bool = true) {
        meetingMode = mode
        if broadcast && session.isHost { session.send(.mode(mode)) }
    }

    /// Switches the host AI (new session + instructions), the speech recognizer and every label at once.
    func setLanguage(_ newLanguage: HostLanguage) {
        guard newLanguage != language else { return }
        LanguageSetting.shared.language = newLanguage
        hostAI.language = newLanguage
        speech.language = newLanguage
        hostTranscript.append(TranscriptEntry(role: .system, text: L("호스트 언어: 한국어 · ", "Host language: English · ") + hostAI.backendLabel))
        showToast(L("언어: 한국어", "Language: English"))
    }

    // MARK: - Search / selection

    func search(_ query: String, limit: Int = 12) -> [CodeSearchHit] {
        CodeSearcher().search(query, in: graph, limit: limit)
    }

    func select(_ id: NodeID?) {
        selectedNodeID = id
    }

    func setHighlights(_ ids: [NodeID], broadcast: Bool = true) {
        highlightedNodeIDs = Set(ids)
        if broadcast { session.send(.highlight(nodeIDs: ids, by: localParticipant.id)) }
    }

    // MARK: - Summon / beacons

    func summon(_ id: NodeID, reason: String, by: ParticipantID? = nil, broadcast: Bool = true) {
        guard graph.node(id) != nil else { return }
        summonedNodeID = id
        selectedNodeID = id
        addBeacon(id)
        if broadcast {
            session.send(.summon(nodeID: id, by: by ?? localParticipant.id, reason: reason))
        } else if followHost && !session.isHost {
            // Remote summon while following: move this member's view to the node.
            noteFollowEvent(id)
        }
    }

    private func noteFollowEvent(_ id: NodeID) {
        guideTargetID = id
        followEventToken += 1
    }

    func clearSummon() {
        summonedNodeID = nil
    }

    func addBeacon(_ id: NodeID, pinned: Bool = false) {
        if !beacons.contains(id) { beacons.append(id) }
        if pinned { pinnedBeacons.insert(id) }
    }

    func togglePinnedBeacon(_ id: NodeID) {
        if pinnedBeacons.contains(id) { pinnedBeacons.remove(id) } else { addBeacon(id, pinned: true) }
    }

    func removeBeacons(_ ids: [NodeID]) {
        guard !ids.isEmpty else { return }
        let gone = Set(ids)
        beacons.removeAll { gone.contains($0) }
    }

    // MARK: - Host orb

    func dockHost(into clusterID: String, broadcast: Bool = true) {
        guard clusters.contains(where: { $0.id == clusterID }) else { return }
        dockedClusterID = clusterID
        if broadcast && session.isHost { session.send(.orbDock(clusterID: clusterID, docked: true)) }
        if let cluster = dockedCluster {
            hostTranscript.append(TranscriptEntry(role: .system, text: L("호스트가 \(cluster.title)에 도킹했습니다 · 이제 이 클러스터를 문맥으로 답합니다",
                                                                            "Host docked into \(cluster.title) · questions now use this cluster as context")))
        }
    }

    func undockHost(broadcast: Bool = true) {
        guard let previous = dockedClusterID else { return }
        dockedClusterID = nil
        if broadcast && session.isHost { session.send(.orbDock(clusterID: previous, docked: false)) }
    }

    func toggleDock(_ clusterID: String) {
        if dockedClusterID == clusterID { undockHost() } else { dockHost(into: clusterID) }
    }

    // MARK: - Host AI

    func askHost(_ text: String, fromRemote: Bool = false) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hostTranscript.append(TranscriptEntry(role: .user, text: trimmed))
        if !session.isHost && !fromRemote {
            session.askHost(trimmed)
            hostTranscript.append(TranscriptEntry(role: .system, text: L("호스트에게 전송했습니다…", "Sent to the host…")))
            return
        }
        beginThinking()
        var situation: [String] = []
        if let docked = dockedCluster {
            situation.append(L("호스트 오브가 클러스터 \"\(docked.title)\" (id \(docked.id))에 도킹되어 있습니다. 그 클러스터 위주로 답하세요.",
                               "The host orb is docked in cluster \"\(docked.title)\" (id \(docked.id)); prefer answers about it."))
        }
        if let selected = selectedNodeID, let node = graph.node(selected) {
            situation.append(L("사용자가 \(node.name) (id \(selected.raw))을(를) 선택한 상태입니다.", "The person has \(node.name) (id \(selected.raw)) selected."))
            let digest = relationSummary(for: selected)
            if !digest.isEmpty { situation.append(digest) }
        }
        // Streaming: one host bubble is created up front and filled in as tokens arrive.
        let entryID = beginHostEntry()
        let reply = await hostAI.streamChat(trimmed, situation: situation.joined(separator: " "), graph: graph, clusters: clusters, docked: dockedCluster) { [weak self] partial in
            self?.updateHostEntry(entryID, text: partial)
        }
        finishHostEntry(entryID, text: reply.text, nodeIDs: reply.nodeIDs, broadcast: true)
    }

    /// Stops any ongoing speech and marks the host as thinking.
    private func beginThinking() {
        hostVoice.stop()
        speakingTask?.cancel()
        hostActivity = .thinking
    }

    private func beginHostEntry() -> UUID {
        let entry = TranscriptEntry(role: .host, text: "")
        hostTranscript.append(entry)
        return entry.id
    }

    private func updateHostEntry(_ id: UUID, text: String) {
        guard let index = hostTranscript.lastIndex(where: { $0.id == id }) else { return }
        hostTranscript[index].text = text
        // First token: thinking → speaking while the rest streams in.
        if !text.isEmpty && hostActivity == .thinking { hostActivity = .speaking }
    }

    private func finishHostEntry(_ id: UUID, text: String, nodeIDs: [NodeID], broadcast: Bool) {
        if let index = hostTranscript.lastIndex(where: { $0.id == id }) {
            hostTranscript[index].text = text
            hostTranscript[index].nodeIDs = nodeIDs
        } else {
            hostTranscript.append(TranscriptEntry(role: .host, text: text, nodeIDs: nodeIDs))
        }
        if hostTranscript.count > 200 { hostTranscript.removeFirst(hostTranscript.count - 200) }
        if !nodeIDs.isEmpty { highlightedNodeIDs = Set(nodeIDs) }
        if broadcast && session.isHost { session.send(.hostSpeech(text: text, nodeIDs: nodeIDs)) }
        startSpeaking(text)
    }

    func askHostAboutSelection() async {
        guard let id = selectedNodeID, let node = graph.node(id) else { return }
        hostTranscript.append(TranscriptEntry(role: .user, text: L("\(node.name) 설명", "Explain \(node.name)")))
        beginThinking()
        let reply = await hostAI.explain(id, graph: graph)
        appendHostSpeech(reply.text, nodeIDs: reply.nodeIDs, broadcast: true)
    }

    func reviewSelection() async {
        guard let id = selectedNodeID, let node = graph.node(id) else { return }
        hostTranscript.append(TranscriptEntry(role: .user, text: L("\(node.name) 리뷰", "Review \(node.name)")))
        beginThinking()
        let reply = await hostAI.review(id, graph: graph, projectRoot: projectRootURL)
        appendHostSpeech(reply.text, nodeIDs: reply.nodeIDs, broadcast: true)
    }

    /// Adds a host bubble, highlights the grounding nodes and animates "speaking" for a duration scaled to text length.
    func appendHostSpeech(_ text: String, nodeIDs: [NodeID], broadcast: Bool) {
        hostTranscript.append(TranscriptEntry(role: .host, text: text, nodeIDs: nodeIDs))
        if hostTranscript.count > 200 { hostTranscript.removeFirst(hostTranscript.count - 200) }
        if !nodeIDs.isEmpty { highlightedNodeIDs = Set(nodeIDs) }
        if broadcast && session.isHost {
            session.send(.hostSpeech(text: text, nodeIDs: nodeIDs))
        }
        startSpeaking(text)
    }

    /// TTS when enabled (presence follows the utterance), else an estimated speaking duration.
    private func startSpeaking(_ text: String) {
        hostActivity = .speaking
        speakingTask?.cancel()
        if speakReplies && hostVoice.isAvailable && !text.isEmpty {
            hostVoice.speak(text)
            // Safety net in case the synthesizer never calls back (e.g. muted simulator).
            speakingTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, !Task.isCancelled, !self.hostVoice.isSpeaking else { return }
                if self.hostActivity == .speaking { self.hostActivity = .idle }
            }
            return
        }
        let seconds = min(12, max(1.5, Double(text.count) * 0.045))
        speakingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            if self.hostActivity == .speaking { self.hostActivity = .idle }
        }
    }

    // MARK: - Laser pointer

    /// Local pointer hit (nil = pointer released). Broadcasts `.pointer` at most 10× per second.
    func setLocalPointer(_ position: SIMD3<Float>?) {
        localPointer = position
        guard let position else { return }
        let now = ContinuousClock.now
        guard now - lastPointerSend >= .milliseconds(100) else { return }
        lastPointerSend = now
        session.send(.pointer(by: localParticipant.id, position: position))
    }

    // MARK: - Voice

    func toggleVoice() {
        speech.toggle()
    }

    /// Routes a transcript to an intent. Called from the speech listener and the text field's "/" commands.
    func handleVoice(_ text: String) async {
        switch router.parse(text) {
        case .find(let query):
            hostTranscript.append(TranscriptEntry(role: .user, text: L("찾기: \(query)", "Find: \(query)")))
            beginThinking()
            let reply = await hostAI.locate(query, graph: graph)
            if let first = reply.nodeIDs.first {
                summon(first, reason: query)
                highlightedNodeIDs = Set(reply.nodeIDs.dropFirst())
            }
            appendHostSpeech(reply.text, nodeIDs: reply.nodeIDs, broadcast: true)
            if !reply.nodeIDs.isEmpty { session.send(.highlight(nodeIDs: reply.nodeIDs, by: localParticipant.id)) }
        case .explain(let query):
            if let query, let hit = search(query, limit: 1).first { selectedNodeID = hit.nodeID }
            await askHostAboutSelection()
        case .dock(let query):
            if let target = resolveCluster(query) { dockHost(into: target.id) } else { await askHost(text) }
        case .undock:
            undockHost()
        case .theme(let hue, let dark):
            setTheme(dark || hue == nil ? .dark : .tinted(hue: hue ?? 0))
        case .tour:
            await startTour()
        case .time(let dial):
            setTimeDial(dial)
        case .ask(let question):
            await askHost(question)
        }
    }

    private func resolveCluster(_ query: String?) -> CodeCluster? {
        if let query, !query.isEmpty {
            let q = query.lowercased()
            if let byTitle = clusters.first(where: { $0.title.lowercased().contains(q) }) { return byTitle }
            if let hit = search(query, limit: 1).first, let c = clusters.first(where: { $0.memberNodeIDs.contains(hit.nodeID) }) { return c }
        }
        if let selected = selectedNodeID { return clusters.first { $0.memberNodeIDs.contains(selected) } }
        return nil
    }

    // MARK: - Tour

    func startTour() async {
        beginThinking()
        let planned = await hostAI.planTour(graph: graph)
        setTour(planned, broadcast: true)
        goToStep(0, broadcast: true)
    }

    func setTour(_ newTour: LearningTour?, broadcast: Bool) {
        tour = newTour
        currentStep = 0
        if newTour != nil { setMeetingMode(.lecture, broadcast: broadcast) }
        if broadcast && session.isHost, let newTour { session.send(.tour(newTour)) }
    }

    func endTour() {
        setTour(nil, broadcast: false)
        setMeetingMode(.analysis)
    }

    func nextStep() { goToStep(currentStep + 1, broadcast: true) }
    func previousStep() { goToStep(currentStep - 1, broadcast: true) }

    func goToStep(_ step: Int, broadcast: Bool) {
        guard let tour, tour.steps.indices.contains(step) else { return }
        currentStep = step
        let stop = tour.steps[step]
        if session.isHost || followHost {
            selectedNodeID = stop.nodeID
            summonedNodeID = stop.nodeID
            addBeacon(stop.nodeID)
            highlightedNodeIDs = [stop.nodeID]
        }
        if broadcast && session.isHost {
            session.send(.tourStep(step))
            appendHostSpeech("\(stop.title): \(stop.narration)", nodeIDs: [stop.nodeID], broadcast: true)
        } else {
            appendHostSpeech("\(stop.title): \(stop.narration)", nodeIDs: [stop.nodeID], broadcast: false)
            if !broadcast && followHost && !session.isHost { noteFollowEvent(stop.nodeID) }
        }
    }

    func setFollowHost(_ follow: Bool) {
        followHost = follow
        if session.isHost { session.send(.followHost(follow)) }
    }

    // MARK: - Pins

    func addPin(nodeID: NodeID, text: String, line: Int? = nil) {
        let pin = ReviewPin(nodeID: nodeID, line: line, author: localParticipant.id, authorName: localParticipant.displayName, text: text)
        addPin(pin, broadcast: true)
    }

    func addPin(_ pin: ReviewPin, broadcast: Bool) {
        guard !pins.contains(where: { $0.id == pin.id }) else { return }
        pins.append(pin)
        if meetingMode == .analysis { setMeetingMode(.review, broadcast: broadcast) }
        if broadcast { session.send(.pin(pin)) }
    }

    func resolvePin(_ id: UUID, resolved: Bool, broadcast: Bool = true) {
        guard let index = pins.firstIndex(where: { $0.id == id }) else { return }
        pins[index].resolved = resolved
        if broadcast { session.send(.resolvePin(id, resolved: resolved)) }
    }

    func pins(for nodeID: NodeID) -> [ReviewPin] { pins.filter { $0.nodeID == nodeID } }

    /// Host or the pin's author may delete it.
    func canDelete(_ pin: ReviewPin) -> Bool { session.isHost || pin.author == localParticipant.id }

    /// Removes a pin locally. Peers receive `.resolvePin(resolved: true)` (the wire format has no delete case).
    func deletePin(_ id: UUID) {
        guard let pin = pins.first(where: { $0.id == id }), canDelete(pin) else { return }
        pins.removeAll { $0.id == id }
        session.send(.resolvePin(id, resolved: true))
    }

    var pinsMarkdown: String { PinsExporter.markdown(pins: pins, graph: graph, language: language) }
    var pinsFilename: String { PinsExporter.suggestedFilename(for: graph, language: language) }

    // MARK: - Participants

    func upsertParticipant(_ participant: Participant) {
        if let index = participants.firstIndex(where: { $0.id == participant.id }) {
            participants[index] = participant
        } else {
            participants.append(participant)
            if !participant.isLocal && !participant.id.raw.hasPrefix("sim-") {
                showToast(L("\(participant.displayName) 참가", "\(participant.displayName) joined"))
            }
        }
        if participant.role == .host && !participant.isLocal {
            localParticipant.role = .member
            if let index = participants.firstIndex(where: { $0.id == localParticipant.id }) { participants[index].role = .member }
        }
    }

    func mergeRoster(_ roster: [Participant]) {
        for remote in roster where remote.id != localParticipant.id {
            var copy = remote
            copy.isLocal = false
            upsertParticipant(copy)
        }
    }

    func addSimulatedMember() {
        session.addSimulatedMember()
        if let newest = participants.last, !newest.isLocal {
            showToast(L("\(newest.displayName) 참가 (회의 인원 \(participants.count)명)", "\(newest.displayName) joined (\(participants.count) in meeting)"))
        }
    }

    func showToast(_ text: String, duration: Duration = .seconds(2)) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled else { return }
            if self.toast == text { self.toast = nil }
        }
    }

    // MARK: - Helpers for views

    func node(_ id: NodeID?) -> CodeNode? {
        guard let id else { return nil }
        return graph.node(id)
    }

    var selectedNode: CodeNode? { node(selectedNodeID) }

    /// Cached `graph.stats()`; refreshed whenever the graph is replaced.
    private(set) var stats: GraphStats = SampleGraph.orbitNotes().stats()

    /// Top nodes by `references` fan-in inside `id`'s subtree (folder / file inspectors).
    func hubs(within id: NodeID, limit: Int = 3) -> [(node: CodeNode, fanIn: Int)] {
        graph.subtree(of: id)
            .map { ($0, graph.fanIn(of: $0.id)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }
            .prefix(limit)
            .map { (node: $0.0, fanIn: $0.1) }
    }
}
