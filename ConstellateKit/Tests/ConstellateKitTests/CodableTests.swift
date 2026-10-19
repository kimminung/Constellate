import Foundation
import Testing
@testable import ConstellateKit

@Suite struct CodableTests {
    let graph = SampleGraph.orbitNotes()

    @Test func codeGraphRoundTrips() throws {
        let data = try JSONEncoder().encode(graph)
        let decoded = try JSONDecoder().decode(CodeGraph.self, from: data)
        #expect(decoded.nodes == graph.nodes)
        #expect(decoded.edges == graph.edges)
        #expect(decoded.rootID == graph.rootID)
        #expect(decoded.projectName == graph.projectName)
        // Indices are rebuilt on decode.
        #expect(decoded.children(of: graph.rootID).count == graph.children(of: graph.rootID).count)
        #expect(decoded.incoming(to: "OrbitNotes/Domain/Models/Note.swift#Note").count == graph.incoming(to: "OrbitNotes/Domain/Models/Note.swift#Note").count)
        #expect(GraphDigest.checksum(decoded) == GraphDigest.checksum(graph))
    }

    @Test func edgesKeepTheirRelationAndNodesTheirRole() throws {
        let data = try JSONEncoder().encode(graph)
        let decoded = try JSONDecoder().decode(CodeGraph.self, from: data)
        #expect(decoded.edges.compactMap(\.relation).count == graph.edges.compactMap(\.relation).count)
        #expect(decoded.nodes.compactMap(\.role).count == graph.nodes.compactMap(\.role).count)
        // Graphs encoded before roles / relations existed still decode (both fields are optional).
        let legacyEdge = #"{"from":{"raw":"a"},"to":{"raw":"b"},"kind":"references","weight":1}"#
        let edge = try JSONDecoder().decode(CodeEdge.self, from: Data(legacyEdge.utf8))
        #expect(edge.relation == nil && edge.semantic == .uses)
    }

    @Test func layoutRoundTrips() throws {
        let layout = ConstellationLayoutEngine().layout(graph)
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(ConstellationLayout.self, from: data)
        #expect(decoded.placements == layout.placements)
        #expect(decoded.configuration == layout.configuration)
        #expect(decoded.boundsMin == layout.boundsMin)
        #expect(decoded.boundsMax == layout.boundsMax)
        #expect(decoded.shellCount == layout.shellCount)
    }

    @Test func statsRoundTrip() throws {
        let stats = graph.stats()
        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(GraphStats.self, from: data)
        #expect(decoded == stats)
        #expect(stats.fileCount == graph.fileCount)
        #expect(stats.totalLines == graph.totalLines)
        #expect(stats.count(of: .file) == graph.fileCount)
        #expect(stats.oldestModified != nil && stats.newestModified != nil)
        #expect(try #require(stats.oldestModified) < #require(stats.newestModified))
    }

    @Test func digestIsDeterministicAndSensitive() {
        let a = GraphDigest.checksum(graph)
        #expect(a == GraphDigest.checksum(SampleGraph.orbitNotes()))
        var nodes = graph.nodes
        nodes[5].lineCount += 1
        let mutated = CodeGraph(projectName: graph.projectName, rootID: graph.rootID, nodes: nodes, edges: graph.edges)
        #expect(GraphDigest.checksum(mutated) != a)
        let empty = CodeGraph(projectName: "x", rootID: "x", nodes: [], edges: [])
        #expect(GraphDigest.checksum(empty) == GraphDigest.checksum(CodeGraph(projectName: "y", rootID: "y", nodes: [], edges: [])))
    }

    @Test func messagesRoundTrip() throws {
        let tour = TourBuilder().tour(for: graph, maxSteps: 3)
        let messages: [ConstellateMessage] = [
            .graphDigest(projectName: graph.projectName, nodeCount: graph.nodes.count, checksum: GraphDigest.checksum(graph)),
            .summon(nodeID: graph.rootID, by: ParticipantID("p1"), reason: "test"),
            .tour(tour),
            .timeDial(0.25),
            .layoutStyle(.celestial),
            .relationMode(.focus)
        ]
        let data = try JSONEncoder().encode(messages)
        let decoded = try JSONDecoder().decode([ConstellateMessage].self, from: data)
        #expect(decoded == messages)
    }
}
