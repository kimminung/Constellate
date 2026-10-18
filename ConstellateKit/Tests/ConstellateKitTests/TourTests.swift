import Foundation
import Testing
@testable import ConstellateKit

@Suite struct TourTests {
    let graph = SampleGraph.orbitNotes()

    @Test func tourStartsAtEntryPointAndIsDeduplicated() throws {
        let tour = TourBuilder().tour(for: graph, maxSteps: 8)
        #expect(!tour.steps.isEmpty)
        #expect(tour.steps.count <= 8)
        #expect(tour.title.contains("OrbitNotes"))
        let first = try #require(tour.steps.first)
        #expect(graph[first.nodeID]?.tags.contains("entry-point") == true)
        #expect(first.narration.contains("entry point"))
        #expect(Set(tour.steps.map(\.nodeID)).count == tour.steps.count)
        for step in tour.steps {
            #expect(graph[step.nodeID] != nil)
            #expect(!step.title.isEmpty)
            #expect(!step.narration.isEmpty)
        }
    }

    @Test func tourVisitsFoldersViewsDataAndTests() {
        let ids = TourBuilder().candidates(for: graph, maxSteps: 10)
        let kinds = ids.compactMap { graph[$0] }
        #expect(kinds.contains { $0.kind == .folder && $0.layer != .test })
        #expect(kinds.contains { $0.kind == .type && $0.tags.contains("SwiftUI.View") })
        #expect(kinds.contains { $0.kind == .file && ($0.layer == .domain || $0.layer == .data) })
        #expect(kinds.contains { $0.layer == .test })
        #expect(ids == TourBuilder().candidates(for: graph, maxSteps: 10), "deterministic")
        #expect(TourBuilder().candidates(for: graph, maxSteps: 3).count == 3)
    }

    @Test func tourWithoutEntryPointStartsAtRoot() {
        let nodes = [
            CodeNode(id: "P", name: "P", kind: .module, path: "P"),
            CodeNode(id: "P/a.swift", name: "a.swift", kind: .file, path: "P/a.swift", parent: "P", lineCount: 5)
        ]
        let g = CodeGraph(projectName: "P", rootID: "P", nodes: nodes, edges: [CodeEdge(from: "P", to: "P/a.swift", kind: .contains)])
        let tour = TourBuilder().tour(for: g)
        #expect(tour.steps.first?.nodeID == "P")
        #expect(tour.steps.count == 2)
    }
}
