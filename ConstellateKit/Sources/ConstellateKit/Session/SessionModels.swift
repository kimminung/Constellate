import Foundation
import simd

/// Role inside a Constellate meeting. The host owns the on-device AI; members talk to it through the host.
public enum ParticipantRole: String, Codable, Sendable {
    case host
    case member
}

public struct ParticipantID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public static func local() -> ParticipantID { ParticipantID(UUID().uuidString) }
    public var description: String { raw }
}

public struct Participant: Identifiable, Hashable, Codable, Sendable {
    public var id: ParticipantID
    public var displayName: String
    public var role: ParticipantRole
    /// Hue offset for the avatar accent (degrees).
    public var hueOffset: Double
    public var isLocal: Bool

    public init(id: ParticipantID, displayName: String, role: ParticipantRole, hueOffset: Double = 0, isLocal: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.hueOffset = hueOffset
        self.isLocal = isLocal
    }
}

/// A review comment pinned to a node (and optionally a line).
public struct ReviewPin: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var nodeID: NodeID
    public var line: Int?
    public var author: ParticipantID
    public var authorName: String
    public var text: String
    public var createdAt: Date
    public var resolved: Bool

    public init(id: UUID = UUID(), nodeID: NodeID, line: Int? = nil, author: ParticipantID, authorName: String, text: String, createdAt: Date = .now, resolved: Bool = false) {
        self.id = id
        self.nodeID = nodeID
        self.line = line
        self.author = author
        self.authorName = authorName
        self.text = text
        self.createdAt = createdAt
        self.resolved = resolved
    }
}

/// One stop of a guided learning tour.
public struct TourStep: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var nodeID: NodeID
    public var title: String
    public var narration: String

    public init(id: UUID = UUID(), nodeID: NodeID, title: String, narration: String) {
        self.id = id
        self.nodeID = nodeID
        self.title = title
        self.narration = narration
    }
}

public struct LearningTour: Hashable, Codable, Sendable {
    public var title: String
    public var steps: [TourStep]
    public init(title: String, steps: [TourStep]) {
        self.title = title
        self.steps = steps
    }
}

/// Session mode chosen by the host.
public enum MeetingMode: String, Codable, Sendable, CaseIterable {
    case analysis
    case review
    case lecture
}

/// Everything that travels between participants. Encoded as JSON over GroupActivities (SharePlay)
/// or Multipeer; the transport is the app's concern.
public enum ConstellateMessage: Codable, Sendable, Hashable {
    /// Full sync sent by the host when someone joins.
    case hello(Participant)
    case roster([Participant])
    case graphDigest(projectName: String, nodeCount: Int, checksum: String)
    case highlight(nodeIDs: [NodeID], by: ParticipantID)
    /// "Summon": bring the node to the requester and raise a beacon for everyone.
    case summon(nodeID: NodeID, by: ParticipantID, reason: String)
    case orbDock(clusterID: String, docked: Bool)
    /// Host AI answered; members see the same bubble.
    case hostSpeech(text: String, nodeIDs: [NodeID])
    case pointer(by: ParticipantID, position: SIMD3<Float>)
    case pin(ReviewPin)
    case resolvePin(UUID, resolved: Bool)
    case theme(ConstellateTheme)
    case timeDial(Float)
    case mode(MeetingMode)
    case tour(LearningTour)
    case tourStep(Int)
    case followHost(Bool)
}

/// Lightweight deterministic checksum for graph digests (FNV-1a 64).
public enum GraphDigest {
    public static func checksum(_ graph: CodeGraph) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ s: String) {
            for b in s.utf8 {
                hash ^= UInt64(b)
                hash = hash &* 0x100000001b3
            }
        }
        for n in graph.nodes {
            mix(n.id.raw)
            mix("\(n.lineCount)")
        }
        mix("\(graph.edges.count)")
        return String(hash, radix: 16)
    }
}
