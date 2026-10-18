import Foundation
import Testing
@testable import ConstellateKit

@Suite struct SampleGraphTests {
    let graph = SampleGraph.orbitNotes()

    @Test func structureIsConsistent() throws {
        #expect(graph.projectName == "OrbitNotes")
        #expect(graph.fileCount >= 35)
        #expect(graph.nodes(ofKind: .type).count >= 40)
        #expect(graph.nodes(ofKind: .function).count >= 40)
        #expect(Set(graph.nodes.map(\.id)).count == graph.nodes.count, "ids are unique")

        for node in graph.nodes where node.id != graph.rootID {
            let parent = try #require(node.parent, "\(node.id) has no parent")
            #expect(graph[parent] != nil, "\(node.id) parent missing")
            #expect(node.kind.order >= (graph[parent]?.kind.order ?? 0))
        }
        for e in graph.edges {
            #expect(graph[e.from] != nil && graph[e.to] != nil, "dangling edge \(e)")
        }
        let s = graph.stats()
        #expect(s.count(of: .imports) > 10)
        #expect(s.count(of: .inherits) > 5)
        #expect(s.count(of: .references) > 40)
        #expect(s.countsByLayer.keys.contains(.presentation))
        #expect(s.countsByLayer.keys.contains(.domain))
        #expect(s.countsByLayer.keys.contains(.data))
        #expect(s.countsByLayer.keys.contains(.infrastructure))
        #expect(s.countsByLayer.keys.contains(.test))
    }

    @Test func realisticFiles() throws {
        for file in graph.nodes(ofKind: .file) {
            #expect(file.lineCount >= 20 && file.lineCount <= 400, "\(file.name)")
            let date = try #require(file.modifiedAt)
            let age = SampleGraph.referenceDate.timeIntervalSince(date)
            #expect(age >= 0 && age <= 90 * 86_400)
            #expect(file.language == "swift")
            for type in graph.children(of: file.id) where type.kind == .type {
                let range = try #require(type.lines)
                #expect(range.start >= 1 && range.end <= file.lineCount, "\(type.id) range \(range)")
            }
        }
        #expect(graph.entryPoints().map(\.name).contains("OrbitNotesApp"))
        #expect(graph["OrbitNotes/Data/Repositories/LocalNoteRepository.swift#LocalNoteRepository"].map { graph.outgoing(from: $0.id, kinds: [.inherits]).map(\.to) } == ["OrbitNotes/Data/Repositories/NoteRepository.swift#NoteRepository"])
        #expect(graph["OrbitNotes/Features/Notes/Views/NotesListView.swift#NotesListView"]?.tags.contains("inherits:View") == true)
        #expect(graph.hubs(limit: 1).first?.name == "Note")
    }

    @Test func graphIsDeterministic() {
        let a = SampleGraph.orbitNotes(), b = SampleGraph.orbitNotes()
        #expect(a.nodes == b.nodes)
        #expect(a.edges == b.edges)
        #expect(GraphDigest.checksum(a) == GraphDigest.checksum(b))
    }

    @Test func sampleSourceSnippets() throws {
        let fileSource = try #require(SampleGraph.sampleSource(for: "OrbitNotes/Domain/Models/Note.swift"))
        let lineCount = fileSource.split(separator: "\n", omittingEmptySubsequences: false).count
        #expect(lineCount >= 15 && lineCount <= 40, "got \(lineCount) lines")
        #expect(fileSource.contains("struct Note: Entity {"))
        #expect(fileSource.contains("import Foundation"))

        let typeSource = try #require(SampleGraph.sampleSource(for: "OrbitNotes/Data/Persistence/NoteStore.swift#NoteStore"))
        #expect(typeSource.hasPrefix("actor NoteStore {"))
        #expect(typeSource.contains("func flush() async throws {"))

        let memberSource = SampleGraph.sampleSource(for: "OrbitNotes/Data/Persistence/NoteStore.swift#NoteStore.flush()")
        #expect(memberSource == typeSource)

        #expect(SampleGraph.sampleSource(for: "OrbitNotes/Data") == nil)
        #expect(SampleGraph.sampleSource(for: "nope") == nil)

        for file in graph.nodes(ofKind: .file) {
            let src = try #require(SampleGraph.sampleSource(for: file.id), "\(file.name)")
            let n = src.split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(n <= 40 && n >= 8, "\(file.name): \(n) lines")
            // Braces balance in every snippet.
            let opens = src.filter { $0 == "{" }.count
            let closes = src.filter { $0 == "}" }.count
            #expect(opens == closes, "\(file.name)")
        }
        let app = try #require(SampleGraph.sampleSource(for: "OrbitNotes/App/OrbitNotesApp.swift"))
        #expect(app.contains("@main"))
    }
}
