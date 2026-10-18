import Foundation
import Testing
@testable import ConstellateKit

@Suite struct ExtractorTests {
    let extractor = SwiftSymbolExtractor()

    @Test func contentViewTypesAndTags() throws {
        let source = try Fixtures.source("App/ContentView.swift")
        let file = extractor.extract(source: source)

        #expect(file.imports == ["SwiftUI"])
        let types = file.symbols.filter { $0.nodeKind == .type }.map(\.name)
        #expect(types == ["ContentView", "ItemRow"])
        #expect(!types.contains("Fake"), "types in comments must be ignored")
        #expect(!types.contains("Bogus"), "types in string literals must be ignored")

        let contentView = try #require(file.symbols.first { $0.name == "ContentView" })
        #expect(contentView.kind == .struct)
        #expect(contentView.inherits == ["View"])
        #expect(contentView.tags.contains("SwiftUI.View"))
        #expect(contentView.tags.contains("@State"))
        #expect(contentView.tags.contains("@Environment"))
        #expect(contentView.tags.contains("struct"))
        #expect(contentView.parentName == nil)

        // Line range: from the declaration to its closing brace.
        let start = try #require(Fixtures.lineNumber(of: "struct ContentView: View", in: source))
        let sourceLines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let end = try #require(sourceLines.indices.first { $0 + 1 > start && sourceLines[$0] == "}" }) + 1
        #expect(contentView.lines.start == start)
        #expect(contentView.lines.end == end)

        let props = file.symbols.filter { $0.kind == .property && $0.parentName == "ContentView" }.map(\.name)
        #expect(props == ["service", "isPresentingEditor", "title", "body"])
        let stateProp = try #require(file.symbols.first { $0.name == "isPresentingEditor" })
        #expect(stateProp.tags.contains("@State"))

        // No members from inside `body` leak out (`item` is only ItemRow's stored property).
        #expect(!file.symbols.contains { $0.name == "item" && $0.parentName == "ContentView" })
        #expect(file.symbols.filter { $0.kind == .property && $0.parentName == "ItemRow" }.map(\.name) == ["item", "body"])

        #expect(file.tags.contains("SwiftUI.View"))
        #expect(file.tags.contains("@State"))
        #expect(file.referencedTypeNames.contains("Item"))
        #expect(file.referencedTypeNames.contains("ItemService"))
        #expect(!file.referencedTypeNames.contains("ContentView"))
        #expect(!file.referencedTypeNames.contains("NavigationStack"), "well-known SwiftUI names are not references")
        #expect(file.lineCount == SwiftSymbolExtractor.lineCount(of: source))
    }

    @Test func nestedTypesAndFunctions() throws {
        let source = try Fixtures.source("Domain/Item.swift")
        let file = extractor.extract(source: source)
        let names = file.symbols.map(\.name)
        #expect(!names.contains("NotReal"), "block comments are stripped")

        let priority = try #require(file.symbols.first { $0.name == "Priority" })
        #expect(priority.kind == .enum)
        #expect(priority.parentName == "Item")
        #expect(priority.inherits == ["Int", "Codable", "Sendable"])

        let renamed = try #require(file.symbols.first { $0.name == "renamed" })
        #expect(renamed.kind == .function)
        #expect(renamed.parentName == "Item")
        #expect(renamed.lines.count == 5)
        #expect(!renamed.tags.contains("async"))

        // `var copy = self` inside the function body is not a property.
        #expect(!file.symbols.contains { $0.name == "copy" })
        let props = file.symbols.filter { $0.kind == .property }.map(\.name)
        #expect(props == ["id", "name", "priority", "isDone"])
    }

    @Test func protocolsActorsAndAsync() throws {
        let source = try Fixtures.source("Domain/ItemStore.swift")
        let file = extractor.extract(source: source)

        let proto = try #require(file.symbols.first { $0.name == "ItemRepository" })
        #expect(proto.kind == .protocol)
        #expect(proto.tags.contains("protocol"))
        let requirements = file.symbols.filter { $0.parentName == "ItemRepository" }
        #expect(requirements.count == 2)
        #expect(requirements.allSatisfy { $0.lines.count == 1 }, "protocol requirements have no body")
        #expect(requirements.allSatisfy { $0.tags.contains("async") })

        let store = try #require(file.symbols.first { $0.name == "ItemStore" })
        #expect(store.kind == .actor)
        #expect(store.tags.contains("actor"))
        #expect(store.tags.contains("async"))
        #expect(store.inherits == ["ItemRepository"])
        let load = try #require(file.symbols.first { $0.name == "load" && $0.parentName == "ItemStore" })
        #expect(load.lines.count == 7)
        // `let data` inside `load` is not a property; `cache` and `fileURL` are.
        let storeProps = file.symbols.filter { $0.kind == .property && $0.parentName == "ItemStore" }.map(\.name)
        #expect(storeProps == ["cache", "fileURL"])
        #expect(file.tags.contains("actor"))
        #expect(file.tags.contains("async"))
    }

    @Test func observableMainActorAndEntryPoint() throws {
        let service = extractor.extract(source: try Fixtures.source("Domain/ItemService.swift"))
        let cls = try #require(service.symbols.first { $0.name == "ItemService" })
        #expect(cls.kind == .class)
        #expect(cls.tags.contains("@Observable"))
        #expect(cls.tags.contains("@MainActor"))
        #expect(service.imports == ["Foundation", "Observation"])
        #expect(service.symbols.filter { $0.kind == .function }.map(\.name) == ["refresh", "add"])

        let app = extractor.extract(source: try Fixtures.source("App/MiniApp.swift"))
        let main = try #require(app.symbols.first { $0.name == "MiniApp" })
        #expect(main.tags.contains("entry-point"))
        #expect(main.tags.contains("SwiftUI.App"))
        #expect(app.tags.contains("entry-point"))
    }

    @Test func extensionsAndTopLevelDeclarations() throws {
        let file = extractor.extract(source: try Fixtures.source("Domain/Formatting.swift"))
        let ext = try #require(file.symbols.first { $0.kind == .extension })
        #expect(ext.name == "Item")
        #expect(ext.nodeKind == .extensionDecl)
        let label = try #require(file.symbols.first { $0.name == "priorityLabel" })
        #expect(label.kind == .property)
        #expect(label.parentName == "Item")
        #expect(label.lines.count == 7)
        let topLevelFunc = try #require(file.symbols.first { $0.name == "formatItem" })
        #expect(topLevelFunc.parentName == nil)
        let constant = try #require(file.symbols.first { $0.name == "defaultPriorityLabel" })
        #expect(constant.parentName == nil)
        #expect(constant.lines.count == 1)
    }

    @Test func testFilesAreTagged() throws {
        let file = extractor.extract(source: try Fixtures.source("Tests/ItemTests.swift"))
        #expect(file.imports == ["Testing", "MiniApp"])
        #expect(file.tags.contains("test"))
        let suite = try #require(file.symbols.first { $0.name == "ItemTests" })
        #expect(suite.tags.contains("test"))
        let tests = file.symbols.filter { $0.kind == .function }
        #expect(tests.count == 2)
        #expect(tests.allSatisfy { $0.tags.contains("test") })
        #expect(file.referencedTypeNames.contains("Item"))
        #expect(file.referencedTypeNames.contains("ItemStore"))
        #expect(!file.referencedTypeNames.contains("UUID"))
    }

    @Test func stripperKeepsLineStructure() {
        let source = """
        let a = "x { y" // trailing { comment
        /* block {
           still block */ let b = 2
        let s = \"\"\"
        multi { line
        \"\"\"
        let c = "\\(value.count) items"
        """
        let lines = SwiftSymbolExtractor.stripCommentsAndStrings(source)
        #expect(lines.count == 7)
        #expect(lines[0] == "let a = \"\" ")
        #expect(lines[1] == "")
        #expect(lines[2] == " let b = 2")
        #expect(lines[6].contains("value.count"))
        #expect(!lines[6].contains("items"))
        #expect(SwiftSymbolExtractor.lineCount(of: source) == 7)
        #expect(SwiftSymbolExtractor.lineCount(of: "a\nb\n") == 2)
        #expect(SwiftSymbolExtractor.lineCount(of: "") == 0)
    }

    @Test func generatesNoSymbolsForEmptySource() {
        let file = extractor.extract(source: "")
        #expect(file.symbols.isEmpty)
        #expect(file.lineCount == 0)
    }
}
