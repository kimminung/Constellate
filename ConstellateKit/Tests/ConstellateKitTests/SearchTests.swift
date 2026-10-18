import Foundation
import Testing
@testable import ConstellateKit

@Suite struct SearchTests {
    let graph = SampleGraph.orbitNotes()
    let searcher = CodeSearcher()

    private func nodes(_ hits: [CodeSearchHit]) -> [CodeNode] { hits.compactMap { graph[$0.nodeID] } }

    @Test func koreanStateViews() {
        let hits = searcher.search("@State 쓰는 뷰", in: graph, limit: 20)
        let found = nodes(hits)
        #expect(!found.isEmpty)
        #expect(found.allSatisfy { $0.kind == .type && $0.tags.contains("SwiftUI.View") && $0.tags.contains("@State") })
        #expect(found.map(\.name).contains("NotesListView"))
        #expect(!found.map(\.name).contains("NoteRowView"), "NoteRowView has no @State")
        #expect(hits.first?.reason.contains("@State") == true)
    }

    @Test func viewThatInheritsView() {
        let hits = searcher.search("view that inherits View", in: graph, limit: 50)
        let found = nodes(hits)
        #expect(found.count >= 10)
        #expect(found.allSatisfy { $0.kind == .type && $0.tags.contains("SwiftUI.View") })
        #expect(hits.allSatisfy { $0.reason.contains("inherits/conforms to View") })
    }

    @Test func exactNameWins() throws {
        let hits = searcher.search("NoteRepository", in: graph)
        let top = nodes(Array(hits.prefix(2))).map(\.name)
        #expect(top.contains("NoteRepository"))
        #expect(top.contains("NoteRepository.swift"))
        let first = try #require(hits.first)
        #expect(first.score >= 10)
        // Substring matches rank below the exact ones.
        let local = try #require(hits.first { $0.nodeID == "OrbitNotes/Data/Repositories/LocalNoteRepository.swift#LocalNoteRepository" })
        #expect(local.score < first.score)
    }

    @Test func koreanFilesInFolder() {
        let hits = searcher.search("폴더 Data 안의 파일", in: graph, limit: 50)
        let found = nodes(hits)
        let expected = graph.nodes(ofKind: .file).filter { $0.path.hasPrefix("OrbitNotes/Data/") }.count
        #expect(expected == 10)
        #expect(found.count == expected)
        #expect(found.allSatisfy { $0.kind == .file && $0.path.hasPrefix("OrbitNotes/Data/") })
    }

    @Test func englishFilesInFolder() {
        let hits = searcher.search("files in folder Domain", in: graph, limit: 50)
        let found = nodes(hits)
        #expect(found.count == 10)
        #expect(found.allSatisfy { $0.kind == .file && $0.path.hasPrefix("OrbitNotes/Domain/") })
        let views = nodes(searcher.search("views in Features", in: graph, limit: 50))
        #expect(!views.isEmpty)
        #expect(views.allSatisfy { $0.path.hasPrefix("OrbitNotes/Features/") && $0.tags.contains("SwiftUI.View") })
    }

    @Test func actorsAndTests() {
        let actors = nodes(searcher.search("actors", in: graph))
        #expect(Set(actors.map(\.name)) == ["NoteStore", "SyncClient"])
        let tests = nodes(searcher.search("테스트", in: graph, limit: 50))
        #expect(!tests.isEmpty)
        #expect(tests.allSatisfy { $0.layer == .test || $0.tags.contains("test") })
    }

    @Test func importsAndUses() {
        let importers = nodes(searcher.search("files that import Domain", in: graph, limit: 50))
        #expect(!importers.isEmpty)
        #expect(importers.allSatisfy { f in graph.outgoing(from: f.id, kinds: [.imports]).contains { graph[$0.to]?.name == "Domain" } })

        let users = nodes(searcher.search("uses NoteStore", in: graph, limit: 50))
        #expect(users.map(\.id).contains("OrbitNotes/Data/Repositories/LocalNoteRepository.swift"))
        #expect(!users.map(\.id).contains("OrbitNotes/Data/Persistence/NoteStore.swift"), "a file does not 'use' its own type")

        let koreanUsers = nodes(searcher.search("Note를 사용하는 뷰", in: graph, limit: 50))
        #expect(!koreanUsers.isEmpty)
        #expect(koreanUsers.allSatisfy { $0.tags.contains("SwiftUI.View") })
        #expect(koreanUsers.map(\.name).contains("NotesListView"))
    }

    @Test func fuzzyMatching() {
        let initials = nodes(searcher.search("NLVM", in: graph))
        #expect(initials.first?.name == "NotesListViewModel" || initials.first?.name == "NotesListViewModel.swift")
        let typo = nodes(searcher.search("NoteRepositry", in: graph))
        #expect(typo.map(\.name).contains("NoteRepository"))
        let camel = nodes(searcher.search("syncclient", in: graph))
        #expect(camel.first?.name.hasPrefix("SyncClient") == true)
    }

    @Test func tagsAndEntryPoint() {
        let entry = nodes(searcher.search("entry point", in: graph))
        #expect(entry.map(\.name).contains("OrbitNotesApp"))
        let korean = nodes(searcher.search("진입점", in: graph))
        #expect(korean.map(\.name).contains("OrbitNotesApp"))
        let asyncFuncs = nodes(searcher.search("async functions", in: graph, limit: 100))
        #expect(!asyncFuncs.isEmpty)
        #expect(asyncFuncs.allSatisfy { $0.kind == .function && $0.tags.contains("async") })
        let observables = nodes(searcher.search("@Observable models", in: graph, limit: 50))
        #expect(observables.map(\.name).contains("NotesListViewModel"))
        #expect(observables.allSatisfy { $0.tags.contains("@Observable") })
    }

    @Test func kindMismatchDropsAndLimitApplies() {
        let hits = searcher.search("Note protocol", in: graph, limit: 50)
        let found = nodes(hits)
        #expect(found.allSatisfy { $0.tags.contains("protocol") })
        #expect(found.map(\.name).contains("NoteRepository"))
        #expect(searcher.search("Note", in: graph, limit: 3).count == 3)
        #expect(searcher.search("", in: graph).isEmpty)
        #expect(searcher.search("the of and", in: graph).isEmpty)
        #expect(searcher.search("zzzzqqqq", in: graph).isEmpty)
    }

    @Test func explainsQueries() {
        let explanation = searcher.explainQuery("@State 쓰는 뷰")
        #expect(explanation.contains("SwiftUI view"))
        #expect(explanation.contains("@State"))
        let structural = searcher.explainQuery("files in folder Data that use Note")
        #expect(structural.contains("file"))
        #expect(structural.contains("inside folder Data"))
        #expect(structural.contains("uses Note"))
        #expect(searcher.explainQuery("").contains("No searchable"))
    }

    @Test func levenshteinAndInitials() {
        #expect(CodeSearcher.levenshtein("kitten", "sitting", limit: 3) == 3)
        #expect(CodeSearcher.levenshtein("abc", "abc", limit: 2) == 0)
        #expect(CodeSearcher.levenshtein("abc", "abcdefg", limit: 2) > 2)
        #expect(CodeSearcher.initials(of: "NotesListViewModel.swift") == "nlvm")
        #expect(CodeSearcher.initials(of: "APIError") == "ae")
    }
}
