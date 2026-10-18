import Foundation
import Testing
@testable import ConstellateKit

@Suite struct ClusterTests {
    let graph = SampleGraph.orbitNotes()
    let builder = ClusterBuilder()

    private func fileIDs(in clusters: [CodeCluster]) -> Set<NodeID> {
        Set(clusters.flatMap(\.memberNodeIDs).filter { graph[$0]?.kind == .file })
    }

    @Test(arguments: ClusterGranularity.allCases)
    func clustersCoverAllFiles(granularity: ClusterGranularity) {
        let clusters = builder.clusters(from: graph, granularity: granularity)
        #expect(!clusters.isEmpty)
        let allFiles = Set(graph.nodes(ofKind: .file).map(\.id))
        if granularity == .type {
            // Type clusters only contain files as fall-backs; every file must be reachable through a cluster anchor instead.
            let anchors = Set(clusters.map(\.anchorNodeID))
            for file in allFiles {
                let covered = anchors.contains(file) || graph.children(of: file).contains { anchors.contains($0.id) }
                #expect(covered, "\(file) not covered by any type cluster")
            }
        } else {
            #expect(fileIDs(in: clusters) == allFiles)
        }
        for c in clusters {
            #expect(c.granularity == granularity)
            #expect(c.id == "cluster:\(granularity.rawValue):\(c.anchorNodeID.raw)")
            #expect(graph[c.anchorNodeID] != nil)
            #expect(c.summary?.isEmpty == false)
            #expect(c.memberNodeIDs.contains(c.anchorNodeID) || granularity == .feature)
            for m in c.memberNodeIDs { #expect(graph[m] != nil) }
        }
        #expect(Set(clusters.map(\.id)).count == clusters.count, "cluster ids must be unique")
    }

    @Test func folderClustersAnchorOnFolders() {
        let clusters = builder.clusters(from: graph, granularity: .folder)
        #expect(clusters.allSatisfy { graph[$0.anchorNodeID]?.kind == .folder })
        let views = clusters.first { $0.anchorNodeID == "OrbitNotes/Features/Notes/Views" }
        #expect(views?.dominantLayer == .presentation)
        #expect(views?.totalLines == 184 + 132 + 158 + 64 + 48)
        #expect(views?.summary?.contains("SwiftUI view") == true)
    }

    @Test func fileClustersAreOnePerFile() {
        let clusters = builder.clusters(from: graph, granularity: .file)
        #expect(clusters.count == graph.fileCount)
        let note = clusters.first { $0.anchorNodeID == "OrbitNotes/Domain/Models/Note.swift" }
        #expect(note?.totalLines == 86)
        #expect(note?.dominantLayer == .domain)
    }

    @Test func typeClustersContainMembers() throws {
        let clusters = builder.clusters(from: graph, granularity: .type)
        let store = try #require(clusters.first { $0.anchorNodeID == "OrbitNotes/Data/Persistence/NoteStore.swift#NoteStore" })
        #expect(store.title == "NoteStore")
        #expect(store.memberNodeIDs.contains("OrbitNotes/Data/Persistence/NoteStore.swift#NoteStore.flush()"))
        #expect(store.summary?.contains("actor") == true)
        #expect(store.dominantLayer == .data)
    }

    @Test func featureClustersAreTopLevelFolders() {
        let clusters = builder.clusters(from: graph, granularity: .feature)
        #expect(clusters.map(\.title).sorted() == ["App", "Core", "Data", "Domain", "Features", "Tests"])
        let tests = clusters.first { $0.title == "Tests" }
        #expect(tests?.dominantLayer == .test)
    }

    @Test func featureClustersDescendThroughSingleSourcesFolder() {
        var nodes: [CodeNode] = [
            CodeNode(id: "P", name: "P", kind: .module, path: "P"),
            CodeNode(id: "P/Sources", name: "Sources", kind: .folder, path: "P/Sources", parent: "P"),
            CodeNode(id: "P/Sources/A", name: "A", kind: .folder, path: "P/Sources/A", parent: "P/Sources"),
            CodeNode(id: "P/Sources/B", name: "B", kind: .folder, path: "P/Sources/B", parent: "P/Sources")
        ]
        nodes.append(CodeNode(id: "P/Sources/A/a.swift", name: "a.swift", kind: .file, path: "P/Sources/A/a.swift", parent: "P/Sources/A", lineCount: 10))
        nodes.append(CodeNode(id: "P/Sources/B/b.swift", name: "b.swift", kind: .file, path: "P/Sources/B/b.swift", parent: "P/Sources/B", lineCount: 20))
        let g = CodeGraph(projectName: "P", rootID: "P", nodes: nodes, edges: [])
        let clusters = builder.clusters(from: g, granularity: .feature)
        #expect(clusters.map(\.title) == ["A", "B"])
    }
}
