import Foundation
import Testing
@testable import ConstellateKit

/// `ConstellationSnapshot` is what the Blender pipeline renders (Blender/data/*.json).
/// Set `CONSTELLATE_SNAPSHOT_DIR` to regenerate those files:
/// `CONSTELLATE_SNAPSHOT_DIR=../Blender/data swift test --filter SnapshotTests`
@Suite struct SnapshotTests {
    let graph = SampleGraph.orbitNotes()

    @Test(arguments: LayoutStyle.allCases)
    func snapshotCoversTheScene(style: LayoutStyle) throws {
        let layout = ConstellationLayoutEngine(style: style).layout(graph)
        var options = EdgeSceneOptions()
        options.bulgeInward = false
        let snapshot = ConstellationSnapshot.make(graph: graph, layout: layout, options: options) { id in
            let src = SampleGraph.sampleSource(for: id) ?? ""
            return Array(src.split(separator: "\n", omittingEmptySubsequences: false).prefix(9).map(String.init))
        }
        #expect(snapshot.nodes.count == graph.nodes.filter { $0.kind.isSpatial }.count)
        #expect(snapshot.arcs.contains { $0.relation == "binds" && $0.flow })
        #expect(snapshot.arcs.allSatisfy { $0.points.count >= 2 })
        #expect(snapshot.nodes.allSatisfy { $0.glyph.hasPrefix("Star_") && $0.starColor.hasPrefix("#") })
        #expect(snapshot.legend.map(\.relation) == RelationKind.legendOrder.map(\.rawValue))
        #expect(Set(snapshot.roles.map(\.glyph)).isSubset(of: Set(StarEncoder.allGlyphNames)))
        // Round-trips as JSON.
        let data = try JSONEncoder().encode(snapshot)
        let back = try JSONDecoder().decode(ConstellationSnapshot.self, from: data)
        #expect(back.nodes.count == snapshot.nodes.count && back.arcs.count == snapshot.arcs.count)
        if let dir = ProcessInfo.processInfo.environment["CONSTELLATE_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("orbitnotes_\(style.rawValue).json")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let pretty = JSONEncoder()
            pretty.outputFormatting = [.sortedKeys]
            try pretty.encode(snapshot).write(to: url)
        }
    }
}
