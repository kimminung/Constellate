import ConstellateKit
import Foundation

/// Supplies the source text shown on code cards and in the inspector.
///
/// Order of preference:
/// 1. A hand-written sample snippet for the built-in "Orbit Notes" demo graph.
/// 2. The real file at `node.path` under the opened project root (sliced to the node's line range).
/// 3. A synthesized placeholder that at least looks like the node (kind, name, tags).
///
/// (The Kit has no `SampleGraph.sampleSource(for:)` yet, so the sample snippets live here.)
nonisolated enum SourceProvider {

    /// Returns the source lines for a node. Runs file I/O synchronously; call from a background task for big files.
    static func source(for node: CodeNode, in graph: CodeGraph, projectRoot: URL?) -> String {
        if projectRoot == nil {
            // Built-in demo graph: the Kit's authored snippets first, then the local extras.
            if let kit = SampleGraph.sampleSource(for: node.id) { return kit }
            if let sample = sampleSource(for: node, in: graph) { return sample }
        }
        if let projectRoot, let real = readFile(for: node, in: graph, projectRoot: projectRoot) { return real }
        return synthesized(for: node, in: graph)
    }

    /// First `count` non-empty-ish lines, for card textures.
    static func previewLines(_ source: String, count: Int) -> [String] {
        var out: [String] = []
        for line in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            out.append(String(line))
            if out.count >= count { break }
        }
        return out
    }

    // MARK: - Real files

    private static func readFile(for node: CodeNode, in graph: CodeGraph, projectRoot: URL) -> String? {
        guard let file = graph.file(containing: node.id) else { return nil }
        // Paths in the graph are relative to the project root and begin with the root folder name.
        var components = file.path.split(separator: "/").map(String.init)
        if components.first == projectRoot.lastPathComponent { components.removeFirst() }
        var url = projectRoot
        for c in components { url.appendPathComponent(c) }
        guard let data = try? Data(contentsOf: url), data.count < 2_000_000,
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        guard node.kind != .file, let range = node.lines else { return text }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let start = max(0, range.start - 1)
        let end = min(lines.count, range.end)
        guard start < end else { return text }
        return lines[start..<end].joined(separator: "\n")
    }

    // MARK: - Sample snippets (Orbit Notes)

    private static let samples: [String: String] = [
        "OrbitNotesApp.swift": """
        import SwiftUI

        @main
        struct OrbitNotesApp: App {
            @State private var store = NoteStore()

            var body: some Scene {
                WindowGroup {
                    NotesRootView()
                        .environment(store)
                }
                #if os(macOS)
                .commands { NotesCommands(store: store) }
                #endif
            }
        }
        """,
        "NoteStore.swift": """
        import Foundation
        import Observation

        @Observable
        final class NoteStore {
            private(set) var notes: [Note] = []
            private let repository: any NoteRepository

            init(repository: any NoteRepository = FileNoteRepository()) {
                self.repository = repository
            }

            func load() async throws {
                notes = try await repository.fetchAll()
            }

            func add(_ note: Note) {
                notes.insert(note, at: 0)
                Task { try? await repository.save(note) }
            }
        }
        """,
        "Note.swift": """
        import Foundation

        struct Note: Identifiable, Codable, Hashable {
            var id: UUID = UUID()
            var title: String
            var body: String
            var tags: Set<String> = []
            var createdAt: Date = .now
            var orbit: Orbit = .inner

            enum Orbit: String, Codable, CaseIterable {
                case inner, middle, outer
            }
        }
        """,
        "NotesRootView.swift": """
        import SwiftUI

        struct NotesRootView: View {
            @Environment(NoteStore.self) private var store
            @State private var selection: Note.ID?
            @State private var query = ""

            var body: some View {
                NavigationSplitView {
                    NoteListView(selection: $selection, query: query)
                        .searchable(text: $query)
                } detail: {
                    if let id = selection, let note = store.notes.first(where: { $0.id == id }) {
                        NoteDetailView(note: note)
                    } else {
                        ContentUnavailableView("Pick a note", systemImage: "note.text")
                    }
                }
                .task { try? await store.load() }
            }
        }
        """
    ]

    private static func sampleSource(for node: CodeNode, in graph: CodeGraph) -> String? {
        guard graph.projectName == "OrbitNotes" else { return nil }
        guard let file = graph.file(containing: node.id), let text = samples[file.name] else { return nil }
        guard node.kind != .file, let range = node.lines else { return text }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let start = max(0, range.start - 1)
        let end = min(lines.count, range.end)
        guard start < end else { return text }
        return lines[start..<end].joined(separator: "\n")
    }

    // MARK: - Synthesized placeholder

    /// A plausible-looking stub so cards never render empty. Clearly marked as a preview.
    static func synthesized(for node: CodeNode, in graph: CodeGraph) -> String {
        let imports = graph.outgoing(from: node.id, kinds: [.imports]).compactMap { graph.node($0.to)?.name }
        let parents = graph.outgoing(from: node.id, kinds: [.inherits]).compactMap { graph.node($0.to)?.name }
        let base = node.name.replacingOccurrences(of: ".swift", with: "")
        var lines: [String] = ["// \(node.path)", "// preview · \(node.lineCount) lines · \(node.layer.rawValue)"]
        switch node.kind {
        case .module:
            lines.append("// Module \(node.name): \(graph.fileCount) files, \(graph.totalLines) lines")
            for child in graph.children(of: node.id).prefix(6) { lines.append("//   ├─ \(child.name)") }
        case .folder:
            lines.append("// Folder \(node.name)")
            for child in graph.children(of: node.id).prefix(7) { lines.append("//   ├─ \(child.name)") }
        case .file:
            for i in imports.prefix(3) { lines.append("import \(i)") }
            if imports.isEmpty { lines.append("import Foundation") }
            lines.append("")
            let types = graph.children(of: node.id).filter { $0.kind == .type || $0.kind == .extensionDecl }
            if types.isEmpty {
                lines.append("struct \(base) {")
                lines.append("    // \(node.lineCount) lines")
                lines.append("}")
            } else {
                for t in types.prefix(3) {
                    let keyword = t.tags.contains("class") ? "final class" : t.tags.contains("enum") ? "enum" : t.tags.contains("protocol") ? "protocol" : "struct"
                    lines.append("\(keyword) \(t.name) {")
                    for m in graph.children(of: t.id).prefix(2) {
                        lines.append(m.kind == .function ? "    func \(m.name)() { }" : "    var \(m.name): Any")
                    }
                    lines.append("}")
                    lines.append("")
                }
            }
        case .type, .extensionDecl:
            let keyword = node.kind == .extensionDecl ? "extension" : node.tags.contains("class") ? "final class" : node.tags.contains("enum") ? "enum" : node.tags.contains("protocol") ? "protocol" : node.tags.contains("actor") ? "actor" : "struct"
            let conf = parents.isEmpty ? "" : ": " + parents.joined(separator: ", ")
            if node.tags.contains("@Observable") { lines.append("@Observable") }
            lines.append("\(keyword) \(node.name)\(conf) {")
            let members = graph.children(of: node.id)
            for m in members.prefix(6) {
                lines.append(m.kind == .function ? "    func \(m.name)() async { }" : "    var \(m.name) = 0")
            }
            if members.isEmpty { lines.append("    // \(node.lineCount) lines") }
            lines.append("}")
        case .function:
            lines.append("func \(node.name)() async throws {")
            lines.append("    // \(node.lineCount) lines")
            lines.append("}")
        case .property:
            lines.append("var \(node.name): Value")
        }
        return lines.joined(separator: "\n")
    }
}
