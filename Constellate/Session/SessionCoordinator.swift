import ConstellateKit
import Foundation
import Observation
#if canImport(GroupActivities)
import GroupActivities
#endif

/// Transport for `ConstellateMessage` over GroupActivities (SharePlay), plus a local simulated mode for demos.
///
/// Protocol notes:
/// - The participant that created the session is the host unless a `.hello` carrying `role == .host` arrives.
/// - Members cannot run the host AI, so they ask through the host with the convention
///   `.hostSpeech(text: "ask:" + question, nodeIDs: [])`. The host answers with a normal `.hostSpeech`.
///   (The Kit enum has no `askHost` case; this prefix keeps the wire format inside `ConstellateMessage`.)
@Observable
@MainActor
final class SessionCoordinator {

    enum State: Equatable {
        case idle
        case activating
        case shared(participants: Int)
        case unavailable(String)

        var label: String {
            switch self {
            case .idle: "Not sharing"
            case .activating: "Starting SharePlay…"
            case .shared(let n): "SharePlay · \(n) connected"
            case .unavailable(let reason): "SharePlay unavailable · \(reason)"
            }
        }
    }

    static let askPrefix = "ask:"

    private(set) var state: State = .idle
    private(set) var isHost = true
    /// Fake members created from the "Add simulated member" debug button.
    private(set) var isSimulated = false

    weak var model: AppModel?

#if canImport(GroupActivities)
    private var session: GroupSession<ConstellateActivity>?
    private var messenger: GroupSessionMessenger?
    private var joinTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var rosterTask: Task<Void, Never>?
#endif

    init() {
        listenForSessions()
    }

    // MARK: - Lifecycle

    /// Starts listening for incoming SharePlay sessions (FaceTime / nearby).
    func listenForSessions() {
#if canImport(GroupActivities)
        guard joinTask == nil else { return }
        joinTask = Task { [weak self] in
            for await session in ConstellateActivity.sessions() {
                guard let self else { return }
                self.configure(session)
            }
        }
#endif
    }

    /// Host side: proposes the activity to the current FaceTime call.
    func startSharing() async {
#if canImport(GroupActivities)
        state = .activating
        isHost = true
        let activity = ConstellateActivity(projectName: model?.graph.projectName ?? "Constellate")
        do {
            let didActivate = try await activity.activate()
            if !didActivate { state = .idle }
        } catch {
            state = .unavailable(error.localizedDescription)
        }
#else
        state = .unavailable("GroupActivities not available")
#endif
    }

    func leave() {
#if canImport(GroupActivities)
        session?.leave()
        receiveTask?.cancel()
        rosterTask?.cancel()
        receiveTask = nil
        rosterTask = nil
        session = nil
        messenger = nil
#endif
        state = .idle
    }

#if canImport(GroupActivities)
    private func configure(_ session: GroupSession<ConstellateActivity>) {
        leave()
        self.session = session
        let messenger = GroupSessionMessenger(session: session)
        self.messenger = messenger

        receiveTask = Task { [weak self] in
            for await (message, _) in messenger.messages(of: ConstellateMessage.self) {
                guard let self else { return }
                self.receive(message)
            }
        }
        // Poll the participant count (no Combine): cheap and good enough for a status label.
        rosterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let session = self.session else { return }
                self.state = .shared(participants: session.activeParticipants.count)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        session.join()
        // If we did not create the session we are a member until a host hello says otherwise.
        if case .activating = state { isHost = true } else { isHost = false }
        if let model {
            send(.hello(model.localParticipant))
            if isHost { sendFullSync() }
        }
    }
#endif

    // MARK: - Sending

    func send(_ message: ConstellateMessage) {
#if canImport(GroupActivities)
        guard let messenger else { return }
        Task {
            do { try await messenger.send(message) } catch { print("[Session] send failed: \(error)") }
        }
#endif
    }

    /// Host → everyone: everything a newcomer needs.
    func sendFullSync() {
        guard let model, isHost else { return }
        send(.roster(model.participants))
        send(.graphDigest(projectName: model.graph.projectName, nodeCount: model.graph.nodes.count, checksum: GraphDigest.checksum(model.graph)))
        send(.theme(model.theme))
        send(.timeDial(model.timeDial))
        send(.mode(model.meetingMode))
        if let tour = model.tour {
            send(.tour(tour))
            send(.tourStep(model.currentStep))
        }
        if let docked = model.dockedClusterID { send(.orbDock(clusterID: docked, docked: true)) }
    }

    /// Member → host question (see protocol notes above).
    func askHost(_ text: String) {
        send(.hostSpeech(text: Self.askPrefix + text, nodeIDs: []))
    }

    // MARK: - Receiving

    func receive(_ message: ConstellateMessage) {
        guard let model else { return }
        switch message {
        case .hello(let participant):
            if participant.role == .host && !participant.isLocal { isHost = false }
            model.upsertParticipant(participant)
            if isHost { sendFullSync() }
        case .roster(let roster):
            model.mergeRoster(roster)
        case .graphDigest(let name, let count, _):
            if model.graph.projectName != name || model.graph.nodes.count != count {
                model.statusMessage = "Host is viewing \(name) (\(count) nodes). Open the same project to stay in sync."
            }
        case .highlight(let ids, _):
            model.highlightedNodeIDs = Set(ids)
        case .summon(let id, let by, let reason):
            model.summon(id, reason: reason, by: by, broadcast: false)
        case .orbDock(let clusterID, let docked):
            if docked { model.dockHost(into: clusterID, broadcast: false) } else { model.undockHost(broadcast: false) }
        case .hostSpeech(let text, let ids):
            if text.hasPrefix(Self.askPrefix) {
                guard isHost else { return }
                let question = String(text.dropFirst(Self.askPrefix.count))
                Task { await model.askHost(question, fromRemote: true) }
            } else {
                model.appendHostSpeech(text, nodeIDs: ids, broadcast: false)
            }
        case .pointer(let by, let position):
            model.pointers[by] = position
        case .pin(let pin):
            model.addPin(pin, broadcast: false)
        case .resolvePin(let id, let resolved):
            model.resolvePin(id, resolved: resolved, broadcast: false)
        case .theme(let theme):
            model.setTheme(theme, broadcast: false)
        case .timeDial(let dial):
            model.setTimeDial(dial, broadcast: false)
        case .mode(let mode):
            model.setMeetingMode(mode, broadcast: false)
        case .tour(let tour):
            model.setTour(tour, broadcast: false)
        case .tourStep(let step):
            model.goToStep(step, broadcast: false)
        case .followHost(let follow):
            model.followHost = follow
        }
    }

    // MARK: - Simulated session (demo)

    private static let demoNames = ["Mina", "Jae", "Sora", "Theo", "Yuna"]

    /// Adds a fake member so screenshots show a meeting without SharePlay.
    func addSimulatedMember() {
        guard let model else { return }
        isSimulated = true
        let index = model.participants.count
        let name = Self.demoNames[index % Self.demoNames.count] + (index >= Self.demoNames.count ? " \(index / Self.demoNames.count + 1)" : "")
        let participant = Participant(id: ParticipantID("sim-\(UUID().uuidString.prefix(6))"), displayName: name, role: .member, hueOffset: Double(index) * 47, isLocal: false)
        model.upsertParticipant(participant)
        if case .idle = state { state = .shared(participants: model.participants.count) }
        else if case .shared = state { state = .shared(participants: model.participants.count) }
    }

    func removeSimulatedMembers() {
        guard let model else { return }
        model.participants.removeAll { $0.id.raw.hasPrefix("sim-") }
        isSimulated = false
        if case .shared = state, !hasLiveSession { state = .idle }
    }

    private var hasLiveSession: Bool {
#if canImport(GroupActivities)
        return session != nil
#else
        return false
#endif
    }
}
