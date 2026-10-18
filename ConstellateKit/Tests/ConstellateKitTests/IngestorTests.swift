import Foundation
import Testing
@testable import ConstellateKit

@Suite struct IngestorTests {
    @Test func buildsTreeFromFixtureProject() async throws {
        let url = try Fixtures.miniAppURL
        var options = IngestOptions()
        options.includedExtensions = ["swift"]
        let graph = try await ProjectIngestor(options: options).ingest(rootURL: url)

        #expect(graph.projectName == "MiniApp")
        #expect(graph.root?.kind == .module)
        #expect(graph.fileCount == 8)
        #expect(graph.nodes(ofKind: .folder).map(\.name).sorted() == ["App", "Domain", "Tests"])

        let types = graph.nodes(ofKind: .type).map(\.name).sorted()
        #expect(types == ["ContentView", "Item", "ItemRepository", "ItemRow", "ItemService", "ItemStore", "ItemTests", "MiniApp", "Priority", "SettingsView"])
        #expect(graph.nodes(ofKind: .extensionDecl).count == 1)

        // Ids follow the documented scheme.
        #expect(graph["MiniApp/Domain/Item.swift#Item"] != nil)
        #expect(graph["MiniApp/Domain/Item.swift#Item.Priority"] != nil)
        #expect(graph["MiniApp/Domain/Item.swift#Item.renamed()"] != nil)
        #expect(graph["MiniApp/Domain/Item.swift#Item.name"] != nil)
        #expect(graph["MiniApp/Domain/Formatting.swift#formatItem()"] != nil)
        #expect(graph["MiniApp/Domain/Formatting.swift#Item(ext)"] != nil)
        #expect(graph["MiniApp/Domain/Formatting.swift#Item(ext).priorityLabel"] != nil)

        // Every node except the root has an existing parent and a contains edge.
        for node in graph.nodes where node.id != graph.rootID {
            let parent = try #require(node.parent, "\(node.id) has no parent")
            #expect(graph[parent] != nil)
            #expect(graph.edges.contains(CodeEdge(from: parent, to: node.id, kind: .contains)))
        }

        // Line counts and dates.
        let itemFile = try #require(graph["MiniApp/Domain/Item.swift"])
        #expect(itemFile.lineCount == 21)
        #expect(itemFile.modifiedAt != nil)
        #expect(itemFile.language == "swift")
        #expect(graph.root?.modifiedAt != nil)
    }

    @Test func layersAndTags() async throws {
        let graph = try await ProjectIngestor().ingest(rootURL: try Fixtures.miniAppURL)
        #expect(graph["MiniApp/App/ContentView.swift"]?.layer == .presentation)
        #expect(graph["MiniApp/App/MiniApp.swift"]?.layer == .presentation)
        #expect(graph["MiniApp/Domain/Item.swift"]?.layer == .domain)
        #expect(graph["MiniApp/Tests/ItemTests.swift"]?.layer == .test)
        #expect(graph["MiniApp/Tests"]?.layer == .test)

        let contentView = try #require(graph["MiniApp/App/ContentView.swift#ContentView"])
        #expect(contentView.tags.contains("SwiftUI.View"))
        #expect(contentView.tags.contains("inherits:View"), "unresolved supertypes are kept as tags")
        #expect(graph["MiniApp/App/ContentView.swift"]?.tags.contains("imports:SwiftUI") == true)
        #expect(graph.entryPoints().map(\.name).contains("MiniApp"))
        #expect(graph["MiniApp/Tests/ItemTests.swift#ItemTests"]?.tags.contains("test") == true)
    }

    @Test func relationEdges() async throws {
        let graph = try await ProjectIngestor().ingest(rootURL: try Fixtures.miniAppURL)

        // inherits: ItemStore → ItemRepository (both in the project)
        let store = try #require(graph["MiniApp/Domain/ItemStore.swift#ItemStore"])
        let inherits = graph.outgoing(from: store.id, kinds: [.inherits])
        #expect(inherits.map(\.to) == ["MiniApp/Domain/ItemStore.swift#ItemRepository"])

        // imports: `@testable import MiniApp` resolves to the root module; SwiftUI does not.
        let testFile = try #require(graph["MiniApp/Tests/ItemTests.swift"])
        #expect(graph.outgoing(from: testFile.id, kinds: [.imports]).map(\.to) == [graph.rootID])
        #expect(graph.outgoing(from: "MiniApp/App/ContentView.swift", kinds: [.imports]).isEmpty)

        // references: ContentView.swift → Item and ItemService; never to a type in the same file.
        let refs = Set(graph.outgoing(from: "MiniApp/App/ContentView.swift", kinds: [.references]).map(\.to))
        #expect(refs.contains("MiniApp/Domain/Item.swift#Item"))
        #expect(refs.contains("MiniApp/Domain/ItemService.swift#ItemService"))
        #expect(!refs.contains("MiniApp/App/ContentView.swift#ItemRow"))
        for e in graph.relationEdges {
            #expect(graph[e.from] != nil && graph[e.to] != nil, "dangling edge \(e)")
        }
        #expect(graph.hubs(limit: 1).first?.name == "Item")
    }

    @Test func reportsProgressAndRejectsFiles() async throws {
        let url = try Fixtures.miniAppURL
        let notDir = url.appendingPathComponent("App/MiniApp.swift")
        await #expect(throws: IngestError.self) {
            _ = try await ProjectIngestor().ingest(rootURL: notDir)
        }

        var options = IngestOptions()
        options.maxFiles = 3
        let capped = try await ProjectIngestor(options: options).ingest(rootURL: url)
        #expect(capped.fileCount == 3)

        options = IngestOptions()
        options.maxFileSize = 10
        let tiny = try await ProjectIngestor(options: options).ingest(rootURL: url)
        #expect(tiny.fileCount == 0)
        #expect(tiny.nodes.count == 1)
    }

    @Test func inferLayerHeuristics() {
        #expect(ProjectIngestor.inferLayer(path: "Features/Notes/Views/NotesListView.swift") == .presentation)
        #expect(ProjectIngestor.inferLayer(path: "Data/Repositories/NoteRepository.swift") == .data)
        #expect(ProjectIngestor.inferLayer(path: "Domain/Models/Note.swift") == .domain)
        #expect(ProjectIngestor.inferLayer(path: "Core/Extensions/Date+Relative.swift") == .infrastructure)
        #expect(ProjectIngestor.inferLayer(path: "Tests/NoteTests.swift") == .test)
        #expect(ProjectIngestor.inferLayer(path: "App/Main.swift", tags: ["entry-point"]) == .presentation)
        #expect(ProjectIngestor.inferLayer(path: "Misc/Thing.swift") == .unknown)
        #expect(ProjectIngestor.inferLayer(path: "Data/Persistence/NoteStore.swift") == .data, "'NoteStore' is not a test")
        #expect(ProjectIngestor.inferLayer(path: "Sources/UnitTests/Helpers.swift") == .test)
        #expect(ProjectIngestor.inferLayer(path: "Sources/Foo/TestSupport.swift") == .test)
        #expect(ProjectIngestor.inferLayer(path: "src/__tests__/foo.js") == .test)
    }
}
