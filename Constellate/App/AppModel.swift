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
        case .free: "Host orb · free"
        case .docked(let id): "Docked in \(clusters.first { $0.id == id }?.title ?? id)"
        case .thinking: "Thinking…"
        case .speaking: "Speaking"
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

    // MARK: Services

    let hostAI = HostAI()
    let hostVoice = HostVoice()
    let speech = SpeechListener()
    let session = SessionCoordinator()
    private let router = VoiceCommandRouter()
    private var speakingTask: Task<Void, Never>?
    private var accessedURL: URL?

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        speakReplies = defaults.object(forKey: "speakReplies") == nil ? true : defaults.bool(forKey: "speakReplies")
        screenshotMode = defaults.bool(forKey: "screenshotMode")
        let sample = SampleGraph.orbitNotes()
        graph = sample
        layout = ConstellationLayoutEngine().layout(sample)
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
        hostAI.prewarm()
        hostTranscript.append(TranscriptEntry(role: .system, text: "Host ready · \(hostAI.backend.label)"))
    }

    private static func deviceUserName() -> String {
#if os(macOS)
        let name = ProcessInfo.processInfo.fullUserName
        return name.isEmpty ? "You" : name
#else
        return "You"
#endif
    }

    // MARK: - Project

    func loadSample() {
        releaseProjectAccess()
        Task { await install(graph: SampleGraph.orbitNotes(), projectRoot: nil) }
    }

    /// Opens a folder picked by the user. Keeps security-scoped access alive so cards can read source later.
    func openProject(url: URL) async {
        guard !isIngesting else { return }
        releaseProjectAccess()
        let accessing = url.startAccessingSecurityScopedResource()
        if accessing { accessedURL = url }
        isIngesting = true
        ingestProgress = nil
        statusMessage = "Reading \(url.lastPathComponent)…"
        do {
            let ingested = try await ProjectIngestor().ingest(rootURL: url) { [weak self] progress in
                guard progress.filesSeen % 20 == 0 else { return }
                Task { @MainActor in self?.ingestProgress = progress }
            }
            await install(graph: ingested, projectRoot: url)
            statusMessage = "\(ingested.projectName): \(ingested.fileCount) files, \(ingested.totalLines) lines"
        } catch {
            statusMessage = error.localizedDescription
        }
        isIngesting = false
        ingestProgress = nil
    }

    private func releaseProjectAccess() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    private func install(graph newGraph: CodeGraph, projectRoot: URL?) async {
        let gran = granularity
        let (newLayout, newClusters) = await Task.detached(priority: .userInitiated) {
            (ConstellationLayoutEngine().layout(newGraph), ClusterBuilder().clusters(from: newGraph, granularity: gran))
        }.value
        graph = newGraph
        layout = newLayout
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
        if session.isHost {
            session.send(.graphDigest(projectName: newGraph.projectName, nodeCount: newGraph.nodes.count, checksum: GraphDigest.checksum(newGraph)))
        }
    }

    func relayout() {
        let g = graph
        Task {
            layout = await Task.detached(priority: .userInitiated) { ConstellationLayoutEngine().layout(g) }.value
            sceneRevision += 1
        }
    }

    func setGranularity(_ value: ClusterGranularity) {
        guard value != granularity else { return }
        granularity = value
        let g = graph
        Task {
            clusters = await Task.detached(priority: .userInitiated) { ClusterBuilder().clusters(from: g, granularity: value) }.value
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
            hostTranscript.append(TranscriptEntry(role: .system, text: "Host docked into \(cluster.title) · questions now use this cluster as context"))
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
            hostTranscript.append(TranscriptEntry(role: .system, text: "Sent to the host…"))
            return
        }
        beginThinking()
        var situation: [String] = []
        if let docked = dockedCluster { situation.append("The host orb is docked in cluster \"\(docked.title)\" (id \(docked.id)); prefer answers about it.") }
        if let selected = selectedNodeID, let node = graph.node(selected) { situation.append("The person has \(node.name) (id \(selected.raw)) selected.") }
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
        hostTranscript.append(TranscriptEntry(role: .user, text: "Explain \(node.name)"))
        beginThinking()
        let reply = await hostAI.explain(id, graph: graph)
        appendHostSpeech(reply.text, nodeIDs: reply.nodeIDs, broadcast: true)
    }

    func reviewSelection() async {
        guard let id = selectedNodeID, let node = graph.node(id) else { return }
        hostTranscript.append(TranscriptEntry(role: .user, text: "Review \(node.name)"))
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
            hostTranscript.append(TranscriptEntry(role: .user, text: "Find: \(query)"))
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
        if let newTour { setMeetingMode(.lecture, broadcast: broadcast) }
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

    var pinsMarkdown: String { PinsExporter.markdown(pins: pins, graph: graph) }
    var pinsFilename: String { PinsExporter.suggestedFilename(for: graph) }

    // MARK: - Participants

    func upsertParticipant(_ participant: Participant) {
        if let index = participants.firstIndex(where: { $0.id == participant.id }) {
            participants[index] = participant
        } else {
            participants.append(participant)
            if !participant.isLocal && !participant.id.raw.hasPrefix("sim-") {
                showToast("\(participant.displayName) joined · 참가")
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
            showToast("\(newest.displayName) joined · 참가 (\(participants.count) in meeting)")
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
