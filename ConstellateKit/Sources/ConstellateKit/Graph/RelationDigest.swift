import Foundation

/// A node's relations grouped the way a developer asks about them — "what does this screen present, which state
/// does it observe, who creates it?" — instead of a flat list of edges.
///
/// Members are folded into the node being inspected: for a file, the edges of the types and functions inside it
/// count as the file's own (relations are mostly type → type), and edges that stay inside the node are skipped.
public struct RelationGroup: Sendable, Hashable, Identifiable {
    public var relation: RelationKind
    /// `true`: this node → others ("Presents"); `false`: others → this node ("Presented by").
    public var outgoing: Bool
    /// The other ends, deduplicated and sorted by name (capped by `RelationDigest.groups(limitPerGroup:)`).
    public var nodes: [NodeID]
    /// How many distinct other ends exist before the cap.
    public var total: Int

    public var id: String { "\(relation.rawValue)-\(outgoing ? "out" : "in")" }
    public var phrase: String { relation.phrase(outgoing: outgoing) }
}

public enum RelationDigest {
    /// Groups ordered like the legend (most informative kind first), outgoing before incoming.
    public static func groups(for id: NodeID, in graph: CodeGraph, limitPerGroup: Int = 12) -> [RelationGroup] {
        let inside = Set(graph.subtree(of: id).map(\.id))
        guard !inside.isEmpty else { return [] }
        var outgoing: [RelationKind: Set<NodeID>] = [:]
        var incoming: [RelationKind: Set<NodeID>] = [:]
        for e in graph.edges {
            guard let rel = e.semantic else { continue }
            let fromInside = inside.contains(e.from), toInside = inside.contains(e.to)
            if fromInside && !toInside { outgoing[rel, default: []].insert(e.to) }
            if toInside && !fromInside { incoming[rel, default: []].insert(e.from) }
        }
        func sortedNames(_ ids: Set<NodeID>) -> [NodeID] {
            ids.sorted { a, b in
                let na = graph[a]?.name ?? a.raw, nb = graph[b]?.name ?? b.raw
                return na != nb ? na < nb : a.raw < b.raw
            }
        }
        var groups: [RelationGroup] = []
        for rel in RelationKind.legendOrder {
            for (isOut, table) in [(true, outgoing), (false, incoming)] {
                guard let ids = table[rel], !ids.isEmpty else { continue }
                groups.append(RelationGroup(relation: rel, outgoing: isOut, nodes: Array(sortedNames(ids).prefix(limitPerGroup)), total: ids.count))
            }
        }
        return groups
    }
}

public extension RelationKind {
    /// Inspector heading for one direction of the relation, e.g. "Presents · 띄우는 화면" / "Presented by · 띄우는 곳".
    func phrase(outgoing: Bool) -> String {
        switch (self, outgoing) {
        case (.conforms, true): "Conforms to · 채택·상속"
        case (.conforms, false): "Adopted by · 채택한 타입"
        case (.extends, true): "Extends · 확장 대상"
        case (.extends, false): "Extended by · 확장"
        case (.composes, true): "Embeds · 포함하는 뷰"
        case (.composes, false): "Embedded in · 포함된 곳"
        case (.presents, true): "Presents · 띄우는 화면"
        case (.presents, false): "Presented by · 띄우는 곳"
        case (.binds, true): "Observes · 관찰하는 상태"
        case (.binds, false): "Observed by · 관찰하는 뷰"
        case (.creates, true): "Creates · 생성"
        case (.creates, false): "Created by · 생성하는 곳"
        case (.delegates, true): "Delegates to · 델리게이트"
        case (.delegates, false): "Delegate of · 위임하는 곳"
        case (.notifies, true): "Notifies · 알림 보냄"
        case (.notifies, false): "Notified by · 알림 받음"
        case (.uses, true): "Uses · 참조"
        case (.uses, false): "Used by · 참조하는 곳"
        case (.imports, true): "Imports · import"
        case (.imports, false): "Imported by · import하는 곳"
        case (.calls, true): "Calls · 호출"
        case (.calls, false): "Called by · 호출하는 곳"
        }
    }
}
