import Foundation
import Testing
@testable import ConstellateKit

/// The Swift port of CoulsonPortfolioWeb's relations.js (roles + relation flavours) on the MiniApp fixture
/// and the Orbit Notes sample.
@Suite struct RelationTests {

    private func miniApp() async throws -> CodeGraph {
        try await ProjectIngestor().ingest(rootURL: Fixtures.miniAppURL)
    }

    private func relation(_ graph: CodeGraph, from: NodeID, to: NodeID) -> RelationKind? {
        graph.edges.first { $0.from == from && $0.to == to && $0.kind != .contains }?.semantic
    }

    @Test func rolesFollowThePortfolioRules() async throws {
        let g = try await miniApp()
        #expect(g["MiniApp/App/MiniApp.swift"]?.role == .app)
        #expect(g["MiniApp/App/ContentView.swift"]?.role == .view)
        #expect(g["MiniApp/App/SettingsView.swift"]?.role == .view)
        #expect(g["MiniApp/Domain/Item.swift"]?.role == .model)
        #expect(g["MiniApp/Domain/ItemService.swift"]?.role == .service)
        #expect(g["MiniApp/Domain/ItemStore.swift"]?.role == .service)
        #expect(g["MiniApp/Domain/Formatting.swift"]?.role == .extensionRole)
        #expect(g["MiniApp/Tests/ItemTests.swift"]?.role == .test)
        // Types: declaration beats file role.
        #expect(g["MiniApp/App/ContentView.swift#ItemRow"]?.role == .view)
        #expect(g["MiniApp/Domain/Formatting.swift#Item(ext)"]?.role == .extensionRole)
        #expect(g["MiniApp"]?.role == nil, "folders and the module carry no role")
    }

    @Test func referencesAreClassified() async throws {
        let g = try await miniApp()
        // @Environment(ItemService.self) → binds; @State var service = ItemService() → binds (binding wins over construction).
        #expect(relation(g, from: "MiniApp/App/ContentView.swift", to: "MiniApp/Domain/ItemService.swift#ItemService") == .binds)
        #expect(relation(g, from: "MiniApp/App/MiniApp.swift", to: "MiniApp/Domain/ItemService.swift#ItemService") == .binds)
        // ContentView() inside WindowGroup { … } → presents.
        #expect(relation(g, from: "MiniApp/App/MiniApp.swift", to: "MiniApp/App/ContentView.swift#ContentView") == .presents)
        // ItemStore(fileURL:) in a service → creates; `any ItemRepository` → uses.
        #expect(relation(g, from: "MiniApp/Domain/ItemService.swift", to: "MiniApp/Domain/ItemStore.swift#ItemStore") == .creates)
        #expect(relation(g, from: "MiniApp/Domain/ItemService.swift", to: "MiniApp/Domain/ItemStore.swift#ItemRepository") == .uses)
        // Tests construct the model and the store.
        #expect(relation(g, from: "MiniApp/Tests/ItemTests.swift", to: "MiniApp/Domain/Item.swift#Item") == .creates)
        // `let item: Item` → uses.
        #expect(relation(g, from: "MiniApp/App/ContentView.swift", to: "MiniApp/Domain/Item.swift#Item") == .uses)
    }

    @Test func conformanceAndExtensionEdges() async throws {
        let g = try await miniApp()
        #expect(relation(g, from: "MiniApp/Domain/ItemStore.swift#ItemStore", to: "MiniApp/Domain/ItemStore.swift#ItemRepository") == .conforms)
        // extension Item (in Formatting.swift) → Item (in Item.swift)
        let ext = try #require(g.edges.first { $0.from == "MiniApp/Domain/Formatting.swift#Item(ext)" && $0.kind == .inherits })
        #expect(ext.to == "MiniApp/Domain/Item.swift#Item")
        #expect(ext.relation == .extends)
        // Every relation edge has a meaning; contains never does.
        for e in g.edges {
            #expect((e.semantic == nil) == (e.kind == .contains), "\(e)")
        }
    }

    @Test func factsPreferStrongestEvidence() {
        let lines = SwiftSymbolExtractor.stripCommentsAndStrings("""
        struct Root: View {
            @Environment(Store.self) private var store
            var body: some View {
                NavigationStack {
                    List { Row(item: Item()) }
                    NavigationLink("Edit") {
                        Editor(item: store.item)
                    }
                }
                .sheet(isPresented: $show) { Settings() }
                // Ghost() is only in a comment
            }
        }
        """)
        let facts = RelationClassifier.referenceFacts(cleanedLines: lines, candidates: ["Store", "Row", "Item", "Editor", "Settings", "Ghost"])
        #expect(facts["Store"] == .binds)
        #expect(facts["Editor"] == .presents)
        #expect(facts["Settings"] == .presents)
        #expect(facts["Row"] == .constructs)
        #expect(facts["Item"] == .constructs)
        #expect(facts["Ghost"] == nil, "comments are stripped before classification")
        #expect(RelationClassifier.relation(for: .constructs, sourceRole: .view, targetRole: .view) == .composes)
        #expect(RelationClassifier.relation(for: .constructs, sourceRole: .service, targetRole: .view) == .creates)
        #expect(RelationClassifier.relation(for: .constructs, sourceRole: .view, targetRole: .model) == .creates)
        #expect(RelationClassifier.inheritanceRelation(superName: "UITableViewDataSource") == .delegates)
        #expect(RelationClassifier.inheritanceRelation(superName: "Equatable") == .conforms)
    }

    @Test func notificationsConnectPostersToObservers() async throws {
        let notes = RelationClassifier.notifications(in: """
        NotificationCenter.default.post(name: .noteDidSave, object: nil)
        NotificationCenter.default.post(name: Notification.Name("syncFinished"), object: nil)
        .onReceive(NotificationCenter.default.publisher(for: .noteDidSave)) { _ in }
        """)
        #expect(notes.posted == ["noteDidSave", "syncFinished"])
        #expect(notes.observed == ["noteDidSave"])

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cst-notify-\(UUID().uuidString)/Notify")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try "struct Saver { func save() { NotificationCenter.default.post(name: .noteDidSave, object: nil) } }".write(to: dir.appendingPathComponent("Saver.swift"), atomically: true, encoding: .utf8)
        try "struct Badge { func watch() { _ = NotificationCenter.default.publisher(for: .noteDidSave) } }".write(to: dir.appendingPathComponent("Badge.swift"), atomically: true, encoding: .utf8)
        let g = try await ProjectIngestor().ingest(rootURL: dir)
        let edge = try #require(g.edges.first { $0.relation == .notifies })
        #expect(edge.from == "Notify/Saver.swift" && edge.to == "Notify/Badge.swift")
        #expect(edge.kind == .calls)
        #expect(RelationKind.notifies.isDependency == false)
    }

    @Test func sampleGraphSpeaksTheFullVocabulary() {
        let g = SampleGraph.orbitNotes()
        var counts: [RelationKind: Int] = [:]
        for e in g.edges { if let r = e.semantic { counts[r, default: 0] += 1 } }
        for kind in [RelationKind.binds, .presents, .composes, .creates, .uses, .conforms, .imports] {
            #expect((counts[kind] ?? 0) > 0, "sample has no \(kind) edges: \(counts)")
        }
        // Views own the presentation layer; every file has a role.
        for file in g.nodes(ofKind: .file) { #expect(file.role != nil, "\(file.id)") }
        #expect(g["OrbitNotes/App/OrbitNotesApp.swift"]?.role == .app)
        #expect(g["OrbitNotes/Features/Notes/Views/NotesListView.swift"]?.role == .view)
        // NotesListView embeds NoteRowView and observes its view model.
        #expect(relation(g, from: "OrbitNotes/Features/Notes/Views/NotesListView.swift", to: "OrbitNotes/Features/Notes/Views/NoteRowView.swift#NoteRowView") == .composes)
        let vm = g.nodes.first { $0.name == "NotesListViewModel" && $0.kind == .type }
        #expect(vm.map { relation(g, from: "OrbitNotes/Features/Notes/Views/NotesListView.swift", to: $0.id) } == .binds)
    }

    @Test func styleTableIsComplete() {
        var lanes: Set<Float> = []
        for kind in RelationKind.allCases {
            let s = kind.style
            #expect(!s.labelKo.isEmpty && !s.labelEn.isEmpty)
            #expect(s.altitude > 0)
            if s.flow || kind == .conforms || kind == .composes { lanes.insert(s.lane) }
        }
        #expect(lanes.count >= 7, "informative kinds fan out into distinct lanes")
        #expect(RelationKind.legendOrder.first == .presents)
        #expect(Set(CodeRole.allCases.map(\.style.glyph)).count == CodeRole.allCases.count)
    }
}

/// Inspector digests and per-node encodings the app reads off the Kit.
@Suite struct InspectorDigestTests {
    let graph = SampleGraph.orbitNotes()

    @Test func digestFoldsMembersIntoTheInspectedFile() throws {
        // Pick any file that has an outgoing classified relation through one of its types.
        let file = try #require(graph.nodes(ofKind: .file).first { f in
            let inside = Set(graph.subtree(of: f.id).map(\.id))
            return graph.edges.contains { $0.relation != nil && inside.contains($0.from) && !inside.contains($0.to) && $0.from != f.id }
        })
        let groups = RelationDigest.groups(for: file.id, in: graph)
        #expect(!groups.isEmpty)
        let inside = Set(graph.subtree(of: file.id).map(\.id))
        for g in groups {
            #expect(g.nodes.allSatisfy { !inside.contains($0) }, "edges inside the file are not relations of the file")
            #expect(g.total >= g.nodes.count)
            #expect(!g.phrase.isEmpty)
        }
        // Legend order: priorities never increase along the list.
        let priorities = groups.map(\.relation.style.priority)
        #expect(priorities == priorities.sorted(by: >))
    }

    @Test func incomingAndOutgoingMirrorEachOther() {
        for e in graph.edges where e.relation == .binds {
            guard let fromFile = graph.file(containing: e.from), let toFile = graph.file(containing: e.to), fromFile.id != toFile.id else { continue }
            let out = RelationDigest.groups(for: fromFile.id, in: graph).first { $0.relation == .binds && $0.outgoing }
            let inc = RelationDigest.groups(for: toFile.id, in: graph).first { $0.relation == .binds && !$0.outgoing }
            #expect(out != nil && inc != nil)
            return
        }
    }

    @Test func starAnchorSitsAboveTheTopLeftCorner() {
        let w: Float = 0.5, s: Float = 0.06
        let a = StarEncoder.anchor(cardWidth: w, size: s)
        #expect(a.x < 0 && a.x > -w / 2)
        #expect(a.y > w * 352 / 512 / 2)
        #expect(a.z > 0)
    }

    @Test func cheapFanInMatchesMetrics() {
        let insights = GraphInsights(graph: graph)
        for node in graph.nodes where node.kind == .file || node.kind == .type {
            #expect(insights.fanIn(of: node.id) == insights.metrics(for: node.id).fanIn)
        }
        for (i, cycle) in insights.cycles.enumerated() {
            #expect(insights.cycleMembers(of: cycle[0]) == cycle)
            #expect(insights.cycle(containing: cycle[0]) == i)
        }
    }
}
