import Foundation

/// Granularity at which floating code is gathered into orbs ("임의의 단위").
public enum ClusterGranularity: String, Codable, Sendable, CaseIterable, Identifiable {
    case folder
    case file
    case type
    /// Feature = top-level folder under the first source root, or a tag group (e.g. all SwiftUI views).
    case feature
    public var id: String { rawValue }
}

/// A group of nodes represented by one Siri-like orb. Tapping the orb docks the host AI into it;
/// pulling it apart releases the AI as a free orb again.
public struct CodeCluster: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var title: String
    public var granularity: ClusterGranularity
    /// The node that anchors the orb (folder, file or type).
    public var anchorNodeID: NodeID
    public var memberNodeIDs: [NodeID]
    public var totalLines: Int
    public var dominantLayer: ArchitectureLayer
    /// Short AI or heuristic summary.
    public var summary: String?

    public init(id: String, title: String, granularity: ClusterGranularity, anchorNodeID: NodeID, memberNodeIDs: [NodeID], totalLines: Int, dominantLayer: ArchitectureLayer, summary: String? = nil) {
        self.id = id
        self.title = title
        self.granularity = granularity
        self.anchorNodeID = anchorNodeID
        self.memberNodeIDs = memberNodeIDs
        self.totalLines = totalLines
        self.dominantLayer = dominantLayer
        self.summary = summary
    }
}
