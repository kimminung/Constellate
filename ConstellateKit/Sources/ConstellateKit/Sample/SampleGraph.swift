import Foundation

/// A built-in demo project so the app shows a constellation before the user picks a folder
/// (and so simulators without file access still have something to explore).
///
/// `orbitNotes()` models "OrbitNotes", a SwiftUI notes app with ~46 files across App / Features /
/// Domain / Data / Core / Tests, complete with types, members, layers, modification dates spread over
/// 90 days (relative to a fixed reference date, so the graph is deterministic), and imports / inherits /
/// references edges. `sampleSource(for:)` returns a short plausible Swift snippet for any file or type
/// node so code cards can be shown without a real project on disk.
public enum SampleGraph {
    /// All sample dates are relative to this instant (2026-10-01 00:00 UTC) so the graph never changes.
    public static let referenceDate = Date(timeIntervalSince1970: 1_790_812_800)
    public static let moduleName = "OrbitNotes"

    public static func orbitNotes() -> CodeGraph {
        Model.shared.graph
    }

    /// A compact (15–40 line) Swift snippet for a file or type node of the sample graph.
    /// Member nodes return their enclosing type's snippet; folders return nil. Unknown ids return nil.
    public static func sampleSource(for nodeID: NodeID) -> String? {
        Model.shared.source(for: nodeID)
    }

    // MARK: - Specification

    struct PropSpec: Sendable {
        var name: String
        var type: String
        var wrapper: String?
        var isStatic: Bool

        /// Parses `"@State isEditing: Bool"`, `"static standard: OrbitTheme"`, `"body: some View"`.
        init(_ text: String) {
            let parts = text.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let left = parts.first ?? text
            type = parts.count > 1 ? parts[1] : "Any"
            var wrapper: String?
            var isStatic = false
            var name = ""
            for token in left.split(separator: " ") {
                if token.hasPrefix("@") { wrapper = String(token) } else if token == "static" { isStatic = true } else { name = String(token) }
            }
            self.name = name
            self.wrapper = wrapper
            self.isStatic = isStatic
        }

        var isComputed: Bool { type.hasPrefix("some ") }
    }

    struct FuncSpec: Sendable {
        var signature: String
        var body: [String]

        init(_ signature: String, body: [String] = []) {
            self.signature = signature
            self.body = body
        }

        var name: String {
            if let paren = signature.firstIndex(of: "(") {
                return String(signature[..<paren]).replacingOccurrences(of: "static ", with: "")
            }
            return signature
        }
        var isAsync: Bool { signature.contains(" async") }
        var returnType: String? {
            guard let r = signature.range(of: "-> ") else { return nil }
            return String(signature[r.upperBound...])
        }
    }

    struct TypeSpec: Sendable {
        var name: String
        var kind: ExtractedSymbol.Kind
        var inherits: [String]
        var tags: Set<String>
        var props: [PropSpec]
        var funcs: [FuncSpec]
        var nested: [TypeSpec]
        var cases: [String]

        init(_ name: String, _ kind: ExtractedSymbol.Kind, inherits: [String] = [], tags: Set<String> = [], props: [String] = [], funcs: [FuncSpec] = [], nested: [TypeSpec] = [], cases: [String] = []) {
            self.name = name
            self.kind = kind
            self.inherits = inherits
            self.tags = tags
            self.props = props.map(PropSpec.init)
            self.funcs = funcs
            self.nested = nested
            self.cases = cases
        }
    }

    struct FileSpec: Sendable {
        var path: String
        var lines: Int
        var daysAgo: Int
        var imports: [String]
        var types: [TypeSpec]
        /// Type names this file refers to (resolved to `references` edges when they exist in the project).
        var uses: [String]
        /// Top-level functions, if any.
        var funcs: [FuncSpec]
    }

    private static func file(_ path: String, _ lines: Int, days: Int, imports: [String], types: [TypeSpec], uses: [String] = [], funcs: [FuncSpec] = []) -> FileSpec {
        FileSpec(path: path, lines: lines, daysAgo: days, imports: imports, types: types, uses: uses, funcs: funcs)
    }

    static let files: [FileSpec] = [
        // MARK: App
        file("App/OrbitNotesApp.swift", 42, days: 2, imports: ["SwiftUI"], types: [
            TypeSpec("OrbitNotesApp", .struct, inherits: ["App"], tags: ["entry-point"], props: ["@State environment: AppEnvironment", "body: some Scene"],
                     funcs: [FuncSpec("init()", body: ["_environment = State(initialValue: .makeDefault())"])])
        ], uses: ["AppEnvironment", "NotesListView", "AppRouter"]),
        file("App/AppRouter.swift", 96, days: 12, imports: ["SwiftUI", "Observation"], types: [
            TypeSpec("AppRouter", .class, tags: ["@Observable", "@MainActor"], props: ["path: [Route]", "selectedNote: Note?"],
                     funcs: [FuncSpec("push(_ route: Route)", body: ["path.append(route)"]), FuncSpec("popToRoot()", body: ["path.removeAll()", "selectedNote = nil"])],
                     nested: [TypeSpec("Route", .enum, inherits: ["Hashable"], cases: ["note(Note.ID)", "search", "settings"])])
        ], uses: ["Note"]),
        file("App/AppEnvironment.swift", 74, days: 20, imports: ["Foundation", "Observation", "Domain", "Data"], types: [
            TypeSpec("AppEnvironment", .class, tags: ["@Observable", "@MainActor"], props: ["noteRepository: any NoteRepository", "syncClient: SyncClient", "settings: SettingsViewModel"],
                     funcs: [FuncSpec("static makeDefault() -> AppEnvironment", body: ["let store = NoteStore(container: PersistenceContainer())", "return AppEnvironment(noteRepository: LocalNoteRepository(store: store), syncClient: SyncClient())"]),
                             FuncSpec("bootstrap() async", body: ["await settings.load()", "try? await syncClient.pull(since: settings.lastSync)"])])
        ], uses: ["NoteRepository", "LocalNoteRepository", "SyncClient", "NoteStore", "PersistenceContainer", "SettingsViewModel"]),

        // MARK: Features / Notes
        file("Features/Notes/Views/NotesListView.swift", 184, days: 1, imports: ["SwiftUI", "Domain"], types: [
            TypeSpec("NotesListView", .struct, inherits: ["View"], props: ["@State viewModel: NotesListViewModel", "@Environment router: AppRouter", "@State searchText: String", "body: some View"],
                     funcs: [FuncSpec("deleteNotes(at offsets: IndexSet)", body: ["for index in offsets {", "    Task { try? await viewModel.delete(viewModel.notes[index]) }", "}"])])
        ], uses: ["NotesListViewModel", "NoteRowView", "Note", "AppRouter", "TagChipView"]),
        file("Features/Notes/Views/NoteDetailView.swift", 132, days: 4, imports: ["SwiftUI", "Domain"], types: [
            TypeSpec("NoteDetailView", .struct, inherits: ["View"], props: ["note: Note", "@State isEditing: Bool", "body: some View"],
                     funcs: [FuncSpec("toggleArchive() async", body: ["try? await ArchiveNoteUseCase(repository: repository)(note, archived: !note.isArchived)"])])
        ], uses: ["Note", "NoteEditorView", "TagChipView", "ArchiveNoteUseCase"]),
        file("Features/Notes/Views/NoteEditorView.swift", 158, days: 3, imports: ["SwiftUI", "Domain"], types: [
            TypeSpec("NoteEditorView", .struct, inherits: ["View"], props: ["@Binding note: Note", "@State viewModel: NoteEditorViewModel", "@Environment dismiss: DismissAction", "body: some View"],
                     funcs: [FuncSpec("save() async", body: ["guard viewModel.validate() else { return }", "try? await viewModel.commit()", "dismiss()"])])
        ], uses: ["NoteEditorViewModel", "Note", "Tag", "OrbitButtonStyle"]),
        file("Features/Notes/Views/NoteRowView.swift", 64, days: 30, imports: ["SwiftUI", "Domain"], types: [
            TypeSpec("NoteRowView", .struct, inherits: ["View"], props: ["note: Note", "body: some View"])
        ], uses: ["Note", "Typography"]),
        file("Features/Notes/Views/TagChipView.swift", 48, days: 45, imports: ["SwiftUI", "Domain"], types: [
            TypeSpec("TagChipView", .struct, inherits: ["View"], props: ["tag: Tag", "isSelected: Bool", "body: some View"])
        ], uses: ["Tag", "OrbitTheme"]),
        file("Features/Notes/ViewModels/NotesListViewModel.swift", 142, days: 2, imports: ["Foundation", "Observation", "Domain"], types: [
            TypeSpec("NotesListViewModel", .class, tags: ["@Observable", "@MainActor"], props: ["notes: [Note]", "isLoading: Bool", "filter: NoteFilter"],
                     funcs: [FuncSpec("load() async", body: ["isLoading = true", "defer { isLoading = false }", "notes = (try? await repository.fetchAll()) ?? []"]),
                             FuncSpec("delete(_ note: Note) async throws", body: ["try await repository.delete(id: note.id)", "notes.removeAll { $0.id == note.id }"]),
                             FuncSpec("refresh() async", body: ["await load()"])],
                     nested: [TypeSpec("NoteFilter", .enum, inherits: ["CaseIterable"], cases: ["all", "active", "archived"])])
        ], uses: ["Note", "NoteRepository", "SearchNotesUseCase"]),
        file("Features/Notes/ViewModels/NoteEditorViewModel.swift", 118, days: 6, imports: ["Foundation", "Observation", "Domain"], types: [
            TypeSpec("NoteEditorViewModel", .class, tags: ["@Observable", "@MainActor"], props: ["draft: Note", "validationError: String?"],
                     funcs: [FuncSpec("validate() -> Bool", body: ["validationError = draft.title.isEmpty ? \"Title is required\" : nil", "return validationError == nil"]),
                             FuncSpec("commit() async throws", body: ["draft.updatedAt = .now", "try await repository.save(draft)"])])
        ], uses: ["Note", "Tag", "CreateNoteUseCase", "NoteRepository"]),

        // MARK: Features / Search
        file("Features/Search/Views/SearchView.swift", 121, days: 8, imports: ["SwiftUI", "Domain"], types: [
            TypeSpec("SearchView", .struct, inherits: ["View"], props: ["@State viewModel: SearchViewModel", "@State query: String", "body: some View"])
        ], uses: ["SearchViewModel", "SearchResultRow", "Note"]),
        file("Features/Search/Views/SearchResultRow.swift", 52, days: 33, imports: ["SwiftUI", "Domain"], types: [
            TypeSpec("SearchResultRow", .struct, inherits: ["View"], props: ["result: SearchResult", "body: some View"])
        ], uses: ["SearchResult", "Typography"]),
        file("Features/Search/ViewModels/SearchViewModel.swift", 104, days: 7, imports: ["Foundation", "Observation", "Domain"], types: [
            TypeSpec("SearchViewModel", .class, tags: ["@Observable", "@MainActor"], props: ["results: [SearchResult]", "isSearching: Bool"],
                     funcs: [FuncSpec("search(_ query: String) async", body: ["isSearching = true", "defer { isSearching = false }", "results = (try? await searchNotes(query)) ?? []"]),
                             FuncSpec("clear()", body: ["results = []"])])
        ], uses: ["SearchResult", "SearchNotesUseCase", "Note"]),

        // MARK: Features / Settings
        file("Features/Settings/Views/SettingsView.swift", 96, days: 15, imports: ["SwiftUI"], types: [
            TypeSpec("SettingsView", .struct, inherits: ["View"], props: ["@Environment settings: SettingsViewModel", "body: some View"])
        ], uses: ["SettingsViewModel", "AppearanceSettingsView", "SyncSettingsView"]),
        file("Features/Settings/Views/AppearanceSettingsView.swift", 72, days: 40, imports: ["SwiftUI", "Core"], types: [
            TypeSpec("AppearanceSettingsView", .struct, inherits: ["View"], props: ["@Binding appearance: Appearance", "body: some View"])
        ], uses: ["Appearance", "OrbitTheme"]),
        file("Features/Settings/Views/SyncSettingsView.swift", 88, days: 9, imports: ["SwiftUI", "Domain"], types: [
            TypeSpec("SyncSettingsView", .struct, inherits: ["View"], props: ["@Environment settings: SettingsViewModel", "@State isSyncing: Bool", "body: some View"],
                     funcs: [FuncSpec("syncNow() async", body: ["isSyncing = true", "defer { isSyncing = false }", "_ = try? await syncNotes()"])])
        ], uses: ["SettingsViewModel", "SyncNotesUseCase", "SyncState"]),
        file("Features/Settings/ViewModels/SettingsViewModel.swift", 110, days: 10, imports: ["Foundation", "Observation"], types: [
            TypeSpec("SettingsViewModel", .class, tags: ["@Observable", "@MainActor"], props: ["appearance: Appearance", "syncEnabled: Bool", "lastSync: Date?"],
                     funcs: [FuncSpec("load()", body: ["appearance = Appearance(rawValue: defaults.string(forKey: \"appearance\") ?? \"\") ?? .system", "syncEnabled = defaults.bool(forKey: \"syncEnabled\")"]),
                             FuncSpec("save()", body: ["defaults.set(appearance.rawValue, forKey: \"appearance\")", "defaults.set(syncEnabled, forKey: \"syncEnabled\")"])]),
            TypeSpec("Appearance", .enum, inherits: ["String", "CaseIterable", "Sendable"], cases: ["system", "light", "dark"])
        ]),

        // MARK: Domain / Models
        file("Domain/Models/Entity.swift", 24, days: 85, imports: ["Foundation"], types: [
            TypeSpec("Entity", .protocol, inherits: ["Identifiable", "Hashable", "Codable", "Sendable"], props: ["id: UUID"])
        ]),
        file("Domain/Models/Note.swift", 86, days: 5, imports: ["Foundation"], types: [
            TypeSpec("Note", .struct, inherits: ["Entity"],
                     props: ["id: UUID", "title: String", "body: String", "tags: [Tag]", "createdAt: Date", "updatedAt: Date", "isArchived: Bool"],
                     funcs: [FuncSpec("excerpt(maxLength: Int) -> String", body: ["let flat = body.replacingOccurrences(of: \"\\n\", with: \" \")", "return flat.count <= maxLength ? flat : String(flat.prefix(maxLength)) + \"…\""])])
        ], uses: ["Tag"]),
        file("Domain/Models/Tag.swift", 38, days: 60, imports: ["Foundation"], types: [
            TypeSpec("Tag", .struct, inherits: ["Entity"], props: ["id: UUID", "name: String", "colorHex: String"])
        ]),
        file("Domain/Models/Notebook.swift", 54, days: 70, imports: ["Foundation"], types: [
            TypeSpec("Notebook", .struct, inherits: ["Entity"], props: ["id: UUID", "title: String", "noteIDs: [UUID]"],
                     funcs: [FuncSpec("contains(_ note: Note) -> Bool", body: ["noteIDs.contains(note.id)"])])
        ], uses: ["Note"]),
        file("Domain/Models/Attachment.swift", 46, days: 82, imports: ["Foundation"], types: [
            TypeSpec("Attachment", .struct, inherits: ["Entity"], props: ["id: UUID", "kind: Kind", "url: URL"],
                     nested: [TypeSpec("Kind", .enum, inherits: ["String", "Codable", "Sendable"], cases: ["image", "audio", "link"])])
        ]),
        file("Domain/Models/SyncState.swift", 40, days: 14, imports: ["Foundation"], types: [
            TypeSpec("SyncState", .enum, inherits: ["Equatable", "Sendable"], props: ["isBusy: Bool"], cases: ["idle", "syncing(progress: Double)", "failed(message: String)", "upToDate(Date)"])
        ]),

        // MARK: Domain / UseCases
        file("Domain/UseCases/CreateNoteUseCase.swift", 68, days: 6, imports: ["Foundation"], types: [
            TypeSpec("CreateNoteUseCase", .struct, inherits: ["Sendable"], props: ["repository: any NoteRepository"],
                     funcs: [FuncSpec("callAsFunction(title: String, body: String, tags: [Tag]) async throws -> Note",
                                      body: ["let note = Note(id: UUID(), title: title, body: body, tags: tags, createdAt: .now, updatedAt: .now, isArchived: false)", "try await repository.save(note)", "return note"])])
        ], uses: ["NoteRepository", "Note", "Tag"]),
        file("Domain/UseCases/SearchNotesUseCase.swift", 112, days: 7, imports: ["Foundation"], types: [
            TypeSpec("SearchResult", .struct, inherits: ["Identifiable", "Hashable", "Sendable"], props: ["id: UUID", "note: Note", "score: Double", "snippet: String"]),
            TypeSpec("SearchNotesUseCase", .struct, inherits: ["Sendable"], props: ["repository: any NoteRepository"],
                     funcs: [FuncSpec("callAsFunction(_ query: String) async throws -> [SearchResult]",
                                      body: ["let tokens = query.lowercased().split(separator: \" \").map(String.init)", "guard !tokens.isEmpty else { return [] }", "let notes = try await repository.fetchAll().filter { !$0.isArchived }", "return notes.map { SearchResult(id: $0.id, note: $0, score: score($0, against: tokens), snippet: $0.excerpt(maxLength: 80)) }", "    .filter { $0.score > 0 }", "    .sorted { $0.score > $1.score }"]),
                             FuncSpec("score(_ note: Note, against tokens: [String]) -> Double", body: ["tokens.reduce(0) { sum, t in", "    sum + (note.title.lowercased().contains(t) ? 2 : 0) + (note.body.lowercased().contains(t) ? 1 : 0)", "}"])])
        ], uses: ["NoteRepository", "Note"]),
        file("Domain/UseCases/SyncNotesUseCase.swift", 94, days: 9, imports: ["Foundation"], types: [
            TypeSpec("SyncNotesUseCase", .struct, inherits: ["Sendable"], props: ["repository: any NoteRepository", "client: SyncClient"],
                     funcs: [FuncSpec("callAsFunction() async throws -> SyncState", body: ["let local = try await repository.fetchAll()", "try await client.push(local)", "for note in try await client.pull(since: nil) { try await repository.save(note) }", "return .upToDate(.now)"])])
        ], uses: ["NoteRepository", "SyncClient", "SyncState", "Note"]),
        file("Domain/UseCases/ArchiveNoteUseCase.swift", 44, days: 25, imports: ["Foundation"], types: [
            TypeSpec("ArchiveNoteUseCase", .struct, inherits: ["Sendable"], props: ["repository: any NoteRepository"],
                     funcs: [FuncSpec("callAsFunction(_ note: Note, archived: Bool) async throws", body: ["var copy = note", "copy.isArchived = archived", "try await repository.save(copy)"])])
        ], uses: ["NoteRepository", "Note"]),

        // MARK: Data / Repositories
        file("Data/Repositories/NoteRepository.swift", 36, days: 50, imports: ["Foundation", "Domain"], types: [
            TypeSpec("NoteRepository", .protocol, inherits: ["Sendable"],
                     funcs: [FuncSpec("fetchAll() async throws -> [Note]"), FuncSpec("fetch(id: UUID) async throws -> Note?"), FuncSpec("save(_ note: Note) async throws"), FuncSpec("delete(id: UUID) async throws")])
        ], uses: ["Note"]),
        file("Data/Repositories/LocalNoteRepository.swift", 148, days: 11, imports: ["Foundation", "Domain"], types: [
            TypeSpec("LocalNoteRepository", .class, inherits: ["NoteRepository"], props: ["store: NoteStore"],
                     funcs: [FuncSpec("fetchAll() async throws -> [Note]", body: ["try await store.records().map(map)"]),
                             FuncSpec("fetch(id: UUID) async throws -> Note?", body: ["try await store.records().first { $0.id == id }.map(map)"]),
                             FuncSpec("save(_ note: Note) async throws", body: ["try await store.upsert(NoteRecord(note))"]),
                             FuncSpec("delete(id: UUID) async throws", body: ["try await store.remove(id: id)"]),
                             FuncSpec("map(_ record: NoteRecord) -> Note", body: ["record.toNote(tags: [])"])])
        ], uses: ["NoteStore", "NoteRecord", "Note", "Tag"]),
        file("Data/Repositories/TagRepository.swift", 72, days: 38, imports: ["Foundation", "Domain"], types: [
            TypeSpec("TagRepository", .protocol, inherits: ["Sendable"], funcs: [FuncSpec("allTags() async throws -> [Tag]")]),
            TypeSpec("LocalTagRepository", .class, inherits: ["TagRepository"], props: ["store: NoteStore"],
                     funcs: [FuncSpec("allTags() async throws -> [Tag]", body: ["let ids = Set(try await store.records().flatMap(\\.tagIDs))", "return ids.map { Tag(id: $0, name: \"tag-\\($0.uuidString.prefix(4))\", colorHex: \"#5EE1FF\") }"])])
        ], uses: ["Tag", "NoteStore"]),

        // MARK: Data / Persistence
        file("Data/Persistence/NoteStore.swift", 176, days: 13, imports: ["Foundation"], types: [
            TypeSpec("NoteStore", .actor, props: ["container: PersistenceContainer", "cache: [UUID: NoteRecord]"],
                     funcs: [FuncSpec("records() async throws -> [NoteRecord]", body: ["if cache.isEmpty { try await loadFromDisk() }", "return Array(cache.values).sorted { $0.updatedAt > $1.updatedAt }"]),
                             FuncSpec("upsert(_ record: NoteRecord) async throws", body: ["cache[record.id] = record", "try await flush()"]),
                             FuncSpec("remove(id: UUID) async throws", body: ["cache[id] = nil", "try await flush()"]),
                             FuncSpec("flush() async throws", body: ["let data = try JSONEncoder().encode(Array(cache.values))", "try data.write(to: container.storeURL, options: .atomic)"])])
        ], uses: ["PersistenceContainer", "NoteRecord", "Migrations"]),
        file("Data/Persistence/PersistenceContainer.swift", 92, days: 55, imports: ["Foundation"], types: [
            TypeSpec("PersistenceContainer", .class, inherits: ["Sendable"], props: ["storeURL: URL"],
                     funcs: [FuncSpec("open() throws", body: ["try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)", "try runMigrations()"]),
                             FuncSpec("runMigrations() throws", body: ["for migration in Migrations.all() { try Migrations.apply(migration, to: storeURL) }"])])
        ], uses: ["Migrations"]),
        file("Data/Persistence/NoteRecord.swift", 58, days: 18, imports: ["Foundation", "Domain"], types: [
            TypeSpec("NoteRecord", .struct, inherits: ["Codable", "Hashable", "Sendable"], props: ["id: UUID", "title: String", "body: String", "tagIDs: [UUID]", "updatedAt: Date", "isArchived: Bool"],
                     funcs: [FuncSpec("toNote(tags: [Tag]) -> Note", body: ["Note(id: id, title: title, body: body, tags: tags.filter { tagIDs.contains($0.id) }, createdAt: updatedAt, updatedAt: updatedAt, isArchived: isArchived)"])])
        ], uses: ["Note", "Tag"]),
        file("Data/Persistence/Migrations.swift", 124, days: 66, imports: ["Foundation"], types: [
            TypeSpec("Migration", .struct, inherits: ["Sendable"], props: ["version: Int", "name: String"]),
            TypeSpec("Migrations", .enum,
                     funcs: [FuncSpec("static all() -> [Migration]", body: ["[Migration(version: 1, name: \"initial\"), Migration(version: 2, name: \"add-archived\")]"]),
                             FuncSpec("static apply(_ migration: Migration, to url: URL) throws", body: ["guard FileManager.default.fileExists(atPath: url.path) else { return }", "// each migration rewrites the JSON store in place"])])
        ]),

        // MARK: Data / Network
        file("Data/Network/SyncClient.swift", 162, days: 4, imports: ["Foundation", "Domain"], types: [
            TypeSpec("SyncClient", .actor, props: ["session: URLSession", "baseURL: URL", "state: SyncState"],
                     funcs: [FuncSpec("push(_ notes: [Note]) async throws", body: ["state = .syncing(progress: 0)", "_ = try await request(.push(notes))", "state = .upToDate(.now)"]),
                             FuncSpec("pull(since: Date?) async throws -> [Note]", body: ["let data = try await request(.pull(since: since))", "return try JSONDecoder().decode([Note].self, from: data)"]),
                             FuncSpec("request(_ endpoint: SyncEndpoint) async throws -> Data", body: ["let (data, response) = try await session.data(for: endpoint.urlRequest(baseURL: baseURL))", "guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.badStatus }", "return data"])])
        ], uses: ["SyncEndpoint", "APIError", "Note", "SyncState"]),
        file("Data/Network/SyncEndpoint.swift", 64, days: 28, imports: ["Foundation", "Domain"], types: [
            TypeSpec("SyncEndpoint", .enum, inherits: ["Sendable"], props: ["path: String", "method: String"],
                     funcs: [FuncSpec("urlRequest(baseURL: URL) throws -> URLRequest", body: ["guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.invalidURL }", "var request = URLRequest(url: url)", "request.httpMethod = method", "return request"])],
                     cases: ["push([Note])", "pull(since: Date?)"])
        ], uses: ["APIError", "Note"]),
        file("Data/Network/APIError.swift", 42, days: 47, imports: ["Foundation"], types: [
            TypeSpec("APIError", .enum, inherits: ["Error", "LocalizedError", "Sendable"], props: ["errorDescription: String?"], cases: ["invalidURL", "badStatus", "decoding(String)"])
        ]),

        // MARK: Core
        file("Core/Extensions/Date+Relative.swift", 34, days: 75, imports: ["Foundation"], types: [
            TypeSpec("Date", .extension, props: ["relativeDescription: String"],
                     funcs: [FuncSpec("isWithin(days: Int) -> Bool", body: ["Date.now.timeIntervalSince(self) < Double(days) * 86_400"])])
        ]),
        file("Core/Extensions/String+Slug.swift", 28, days: 80, imports: ["Foundation"], types: [
            TypeSpec("String", .extension, props: ["slug: String"],
                     funcs: [FuncSpec("truncated(to length: Int) -> String", body: ["count <= length ? self : String(prefix(length)) + \"…\""])])
        ]),
        file("Core/Extensions/Collection+Safe.swift", 22, days: 89, imports: ["Foundation"], types: [
            TypeSpec("Collection", .extension, funcs: [FuncSpec("element(safe index: Index) -> Element?", body: ["indices.contains(index) ? self[index] : nil"])])
        ]),
        file("Core/DesignSystem/OrbitTheme.swift", 78, days: 35, imports: ["SwiftUI", "Domain"], types: [
            TypeSpec("OrbitTheme", .struct, inherits: ["Sendable"], props: ["accent: Color", "background: Color", "cardCornerRadius: CGFloat", "static standard: OrbitTheme"],
                     funcs: [FuncSpec("color(for tag: Tag) -> Color", body: ["Color(hex: tag.colorHex) ?? accent"])])
        ], uses: ["Tag"]),
        file("Core/DesignSystem/OrbitButtonStyle.swift", 46, days: 52, imports: ["SwiftUI"], types: [
            TypeSpec("OrbitButtonStyle", .struct, inherits: ["ButtonStyle"],
                     funcs: [FuncSpec("makeBody(configuration: Configuration) -> some View", body: ["configuration.label", "    .padding(.horizontal, 14)", "    .background(OrbitTheme.standard.accent.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())"])])
        ], uses: ["OrbitTheme"]),
        file("Core/DesignSystem/Typography.swift", 40, days: 58, imports: ["SwiftUI"], types: [
            TypeSpec("Typography", .enum, props: ["static title: Font", "static body: Font", "static caption: Font"])
        ]),

        // MARK: Tests
        file("Tests/NoteTests.swift", 72, days: 5, imports: ["Testing", "Domain"], types: [
            TypeSpec("NoteTests", .struct, tags: ["test"],
                     funcs: [FuncSpec("excerptTruncates()", body: ["let note = Note(id: UUID(), title: \"T\", body: String(repeating: \"a\", count: 200), tags: [], createdAt: .now, updatedAt: .now, isArchived: false)", "#expect(note.excerpt(maxLength: 10).count == 11)"]),
                             FuncSpec("archivedNotesAreExcludedFromSearch() async throws", body: ["let results = try await SearchNotesUseCase(repository: InMemoryNoteRepository())(\"orbit\")", "#expect(results.allSatisfy { !$0.note.isArchived })"])])
        ], uses: ["Note", "Tag", "SearchNotesUseCase", "InMemoryNoteRepository"]),
        file("Tests/SearchNotesUseCaseTests.swift", 96, days: 7, imports: ["Testing", "Domain", "Data"], types: [
            TypeSpec("InMemoryNoteRepository", .class, inherits: ["NoteRepository"], props: ["notes: [Note]"],
                     funcs: [FuncSpec("fetchAll() async throws -> [Note]", body: ["notes"]), FuncSpec("fetch(id: UUID) async throws -> Note?", body: ["notes.first { $0.id == id }"]),
                             FuncSpec("save(_ note: Note) async throws", body: ["notes.removeAll { $0.id == note.id }", "notes.append(note)"]), FuncSpec("delete(id: UUID) async throws", body: ["notes.removeAll { $0.id == id }"])]),
            TypeSpec("SearchNotesUseCaseTests", .struct, tags: ["test"],
                     funcs: [FuncSpec("ranksTitleMatchesFirst() async throws", body: ["let results = try await SearchNotesUseCase(repository: InMemoryNoteRepository())(\"orbit\")", "#expect(results.first?.note.title.contains(\"Orbit\") == true)"]),
                             FuncSpec("emptyQueryReturnsNothing() async throws", body: ["#expect(try await SearchNotesUseCase(repository: InMemoryNoteRepository())(\"\").isEmpty)"])])
        ], uses: ["SearchNotesUseCase", "Note", "NoteRepository"]),
        file("Tests/LocalNoteRepositoryTests.swift", 110, days: 11, imports: ["Testing", "Domain", "Data"], types: [
            TypeSpec("LocalNoteRepositoryTests", .struct, tags: ["test"],
                     funcs: [FuncSpec("saveThenFetchRoundTrips() async throws", body: ["let repo = LocalNoteRepository(store: NoteStore(container: PersistenceContainer()))", "let note = Note(id: UUID(), title: \"Hello\", body: \"\", tags: [], createdAt: .now, updatedAt: .now, isArchived: false)", "try await repo.save(note)", "#expect(try await repo.fetch(id: note.id) == note)"]),
                             FuncSpec("deleteRemovesRecord() async throws", body: ["let repo = LocalNoteRepository(store: NoteStore(container: PersistenceContainer()))", "try await repo.delete(id: UUID())", "#expect(try await repo.fetchAll().isEmpty)"])])
        ], uses: ["LocalNoteRepository", "NoteStore", "PersistenceContainer", "Note"]),
        file("Tests/SyncClientTests.swift", 84, days: 4, imports: ["Testing", "Domain", "Data"], types: [
            TypeSpec("SyncClientTests", .struct, tags: ["test"],
                     funcs: [FuncSpec("pushEncodesNotes() async throws", body: ["let client = SyncClient(session: .mock, baseURL: URL(string: \"https://example.com\")!)", "try await client.push([])"]),
                             FuncSpec("pullDecodesServerPayload() async throws", body: ["let client = SyncClient(session: .mock, baseURL: URL(string: \"https://example.com\")!)", "#expect(try await client.pull(since: nil).isEmpty)"])])
        ], uses: ["SyncClient", "SyncEndpoint", "Note", "APIError"])
    ]

    // MARK: - Model

    /// Builds the graph and the snippet table once; immutable afterwards so it is safe to share.
    private struct Model: Sendable {
        static let shared = Model()

        let graph: CodeGraph
        private let sources: [NodeID: String]
        /// member id → enclosing type id
        private let enclosingType: [NodeID: NodeID]

        func source(for id: NodeID) -> String? {
            if let s = sources[id] { return s }
            if let t = enclosingType[id] { return sources[t] }
            return nil
        }

        init() {
            let module = SampleGraph.moduleName
            var nodes: [CodeNode] = []
            var edges: [CodeEdge] = []
            var ids: Set<NodeID> = []
            var sources: [NodeID: String] = [:]
            var enclosing: [NodeID: NodeID] = [:]
            var typeIDs: [String: NodeID] = [:]
            var typeFile: [NodeID: NodeID] = [:]
            var folderDates: [NodeID: Date] = [:]

            func add(_ node: CodeNode) {
                guard ids.insert(node.id).inserted else { return }
                nodes.append(node)
                if let p = node.parent { edges.append(CodeEdge(from: p, to: node.id, kind: .contains)) }
            }

            add(CodeNode(id: NodeID(module), name: module, kind: .module, path: module))
            let topLevel = Set(SampleGraph.files.compactMap { $0.path.split(separator: "/").first.map(String.init) })

            var pendingInherits: [PendingInherit] = []
            var pendingRefs: [(file: NodeID, name: String)] = []

            for spec in SampleGraph.files {
                let components = spec.path.split(separator: "/").map(String.init)
                let modifiedAt = SampleGraph.referenceDate.addingTimeInterval(-Double(spec.daysAgo) * 86_400)
                var parent = NodeID(module)
                var path = module
                for dir in components.dropLast() {
                    path += "/" + dir
                    let id = NodeID(path)
                    add(CodeNode(id: id, name: dir, kind: .folder, path: path, parent: parent, layer: ProjectIngestor.inferLayer(path: path)))
                    folderDates[id] = max(folderDates[id] ?? .distantPast, modifiedAt)
                    parent = id
                }
                folderDates[NodeID(module)] = max(folderDates[NodeID(module)] ?? .distantPast, modifiedAt)

                let fileName = components.last ?? spec.path
                let filePath = path + "/" + fileName
                let fileID = NodeID(filePath)
                var fileTags: Set<String> = []
                for t in spec.types {
                    fileTags.formUnion(Model.typeTags(t).intersection(["SwiftUI.View", "SwiftUI.App", "@Observable", "@MainActor", "actor", "entry-point", "test", "async"]))
                    for p in t.props { if let w = p.wrapper, ["@State", "@Binding", "@Environment"].contains(w) { fileTags.insert(w) } }
                }
                if components.first == "Tests" { fileTags.insert("test") }
                for imp in spec.imports where !topLevel.contains(imp) { fileTags.insert("imports:\(imp)") }
                let fileLayer = ProjectIngestor.inferLayer(path: spec.path, tags: fileTags)
                add(CodeNode(id: fileID, name: fileName, kind: .file, path: filePath, parent: parent, language: "swift",
                             lines: LineRange(start: 1, end: spec.lines), lineCount: spec.lines, modifiedAt: modifiedAt, layer: fileLayer, tags: fileTags))
                for imp in spec.imports where topLevel.contains(imp) && imp != components.first {
                    edges.append(CodeEdge(from: fileID, to: NodeID("\(module)/\(imp)"), kind: .imports))
                }
                for name in spec.uses { pendingRefs.append((fileID, name)) }

                // Allocate line ranges.
                let header = 3 + spec.imports.count + 1
                let budget = max(spec.types.count * 4, spec.lines - header - 1)
                let weights = spec.types.map { Model.weight($0) }
                let totalWeight = max(1, weights.reduce(0, +))
                var cursor = header + 1

                for (ti, t) in spec.types.enumerated() {
                    let span = max(3, Int(Double(budget) * Double(weights[ti]) / Double(totalWeight)))
                    let range = LineRange(start: cursor, end: min(spec.lines, cursor + span - 1))
                    cursor = range.end + 2
                    let typeID = Model.addType(t, parent: fileID, qualifier: "", filePath: filePath, range: range, modifiedAt: modifiedAt, fileLayer: fileLayer, isTestFile: fileTags.contains("test"),
                                               add: add, typeIDs: &typeIDs, typeFile: &typeFile, enclosing: &enclosing, pendingInherits: &pendingInherits, fileID: fileID)
                    sources[typeID] = Model.render(file: spec, types: [t], includeHeader: false)
                }
                for f in spec.funcs {
                    let id = NodeID("\(filePath)#\(f.name)()")
                    add(CodeNode(id: id, name: f.name, kind: .function, path: filePath, parent: fileID, language: "swift", lines: LineRange(start: cursor, end: cursor + 2), lineCount: 3, modifiedAt: modifiedAt, layer: fileLayer, tags: f.isAsync ? ["async"] : []))
                    cursor += 4
                }
                sources[fileID] = Model.render(file: spec, types: spec.types, includeHeader: true)
            }

            // Folder dates
            for (i, n) in nodes.enumerated() where n.kind == .folder || n.kind == .module {
                if let d = folderDates[n.id] { nodes[i].modifiedAt = d }
            }

            // Inherits
            var tagAdditions: [NodeID: Set<String>] = [:]
            for p in pendingInherits {
                if let target = typeIDs[p.superName], target != p.type {
                    edges.append(CodeEdge(from: p.type, to: target, kind: .inherits))
                } else {
                    tagAdditions[p.type, default: []].insert("inherits:\(p.superName)")
                }
            }
            // References (file → type in another file)
            var seenRefs: Set<CodeEdge> = []
            for (file, name) in pendingRefs {
                guard let target = typeIDs[name], typeFile[target] != file else { continue }
                let e = CodeEdge(from: file, to: target, kind: .references, weight: 1)
                if seenRefs.insert(e).inserted { edges.append(e) }
            }
            for (i, n) in nodes.enumerated() {
                if let extra = tagAdditions[n.id] { nodes[i].tags.formUnion(extra) }
            }

            self.graph = CodeGraph(projectName: module, rootID: NodeID(module), nodes: nodes, edges: edges, generatedAt: SampleGraph.referenceDate)
            self.sources = sources
            self.enclosingType = enclosing
        }

        private static func weight(_ t: TypeSpec) -> Int {
            2 + t.props.count + 3 * t.funcs.count + t.cases.count + t.nested.reduce(0) { $0 + weight($1) }
        }

        static func typeTags(_ t: TypeSpec) -> Set<String> {
            var tags = t.tags
            tags.insert(t.kind.rawValue)
            if t.inherits.contains("View") { tags.insert("SwiftUI.View") }
            if t.inherits.contains("App") { tags.insert("SwiftUI.App") }
            if t.kind == .actor { tags.insert("actor") }
            if t.funcs.contains(where: \.isAsync) { tags.insert("async") }
            for p in t.props { if let w = p.wrapper, ["@State", "@Binding", "@Environment"].contains(w) { tags.insert(w) } }
            if t.name.hasSuffix("Tests") { tags.insert("test") }
            return tags
        }

        /// Adds a type / extension node with its members (and nested types, recursively). Returns the node id.
        @discardableResult
        private static func addType(
            _ t: TypeSpec, parent: NodeID, qualifier: String, filePath: String, range: LineRange, modifiedAt: Date, fileLayer: ArchitectureLayer, isTestFile: Bool,
            add: (CodeNode) -> Void, typeIDs: inout [String: NodeID], typeFile: inout [NodeID: NodeID], enclosing: inout [NodeID: NodeID],
            pendingInherits: inout [PendingInherit], fileID: NodeID
        ) -> NodeID {
            let qualified = qualifier.isEmpty ? t.name : "\(qualifier).\(t.name)"
            let id = NodeID(t.kind == .extension ? "\(filePath)#\(qualified)(ext)" : "\(filePath)#\(qualified)")
            var tags = typeTags(t)
            if isTestFile && t.kind != .extension { tags.insert("test") }
            let layer: ArchitectureLayer = tags.contains("SwiftUI.View") ? .presentation : (isTestFile ? .test : fileLayer)
            add(CodeNode(id: id, name: t.name, kind: t.kind == .extension ? .extensionDecl : .type, path: filePath, parent: parent, language: "swift",
                         lines: range, lineCount: range.count, modifiedAt: modifiedAt, layer: layer, tags: tags))
            if t.kind != .extension {
                typeIDs[t.name] = id
                typeFile[id] = fileID
                for s in t.inherits { pendingInherits.append(PendingInherit(type: id, superName: s)) }
            }

            var cursor = range.start + 1
            for n in t.nested {
                let span = min(max(3, 2 + n.cases.count + n.props.count), max(3, range.end - cursor))
                let nestedRange = LineRange(start: cursor, end: cursor + span - 1)
                cursor = nestedRange.end + 2
                addType(n, parent: id, qualifier: qualified, filePath: filePath, range: nestedRange, modifiedAt: modifiedAt, fileLayer: fileLayer, isTestFile: isTestFile,
                        add: add, typeIDs: &typeIDs, typeFile: &typeFile, enclosing: &enclosing, pendingInherits: &pendingInherits, fileID: fileID)
            }
            for p in t.props {
                let line = min(range.end, cursor)
                var ptags: Set<String> = []
                if let w = p.wrapper { ptags.insert(w) }
                let pid = NodeID("\(filePath)#\(qualified).\(p.name)")
                add(CodeNode(id: pid, name: p.name, kind: .property, path: filePath, parent: id, language: "swift", lines: LineRange(start: line, end: line), lineCount: 1, modifiedAt: modifiedAt, layer: layer, tags: ptags))
                enclosing[pid] = id
                cursor += 1
            }
            cursor += 1
            if !t.funcs.isEmpty {
                let remaining = max(t.funcs.count * 2, range.end - cursor)
                let per = max(2, remaining / t.funcs.count)
                for f in t.funcs {
                    let start = min(range.end, cursor)
                    let end = min(range.end, start + per - 1)
                    let fid = NodeID("\(filePath)#\(qualified).\(f.name)()")
                    var ftags: Set<String> = []
                    if f.isAsync { ftags.insert("async") }
                    if isTestFile && t.name.hasSuffix("Tests") { ftags.insert("test") }
                    add(CodeNode(id: fid, name: f.name, kind: .function, path: filePath, parent: id, language: "swift", lines: LineRange(start: start, end: end), lineCount: end - start + 1, modifiedAt: modifiedAt, layer: layer, tags: ftags))
                    enclosing[fid] = id
                    cursor = end + 2
                }
            }
            return id
        }

        struct PendingInherit { var type: NodeID; var superName: String }

        // MARK: Rendering

        static func render(file: FileSpec, types: [TypeSpec], includeHeader: Bool) -> String {
            var lines: [String] = []
            if includeHeader {
                lines.append("//  \(file.path.split(separator: "/").last ?? "")")
                lines.append("//  OrbitNotes")
                lines.append("")
                for imp in file.imports { lines.append("import \(imp)") }
                lines.append("")
            }
            for (i, t) in types.enumerated() {
                if i > 0 { lines.append("") }
                lines.append(contentsOf: render(type: t, indent: ""))
            }
            for f in file.funcs {
                lines.append("")
                lines.append(contentsOf: render(func: f, indent: ""))
            }
            // Keep cards compact: cap at 40 lines, trimming from the middle of the longest body.
            if lines.count > 40 {
                let keepHead = 30
                let keepTail = 9
                lines = Array(lines.prefix(keepHead)) + ["    // …"] + Array(lines.suffix(keepTail))
            }
            return lines.joined(separator: "\n")
        }

        private static func render(type t: TypeSpec, indent: String) -> [String] {
            var out: [String] = []
            var attrs: [String] = []
            if t.tags.contains("entry-point") { attrs.append("@main") }
            if t.tags.contains("@Observable") { attrs.append("@Observable") }
            if t.tags.contains("@MainActor") { attrs.append("@MainActor") }
            for a in attrs { out.append(indent + a) }
            var decl = indent
            if t.kind == .class { decl += "final " }
            decl += "\(t.kind.rawValue) \(t.name)"
            if !t.inherits.isEmpty { decl += ": " + t.inherits.joined(separator: ", ") }
            decl += " {"
            out.append(decl)
            let inner = indent + "    "
            for n in t.nested {
                out.append(contentsOf: render(type: n, indent: inner))
                out.append("")
            }
            for c in t.cases { out.append("\(inner)case \(c)") }
            if !t.cases.isEmpty && (!t.props.isEmpty || !t.funcs.isEmpty) { out.append("") }
            for p in t.props {
                if p.isComputed {
                    out.append("\(inner)var \(p.name): \(p.type) {")
                    out.append(contentsOf: computedBody(for: p, type: t).map { inner + "    " + $0 })
                    out.append("\(inner)}")
                } else if t.kind == .protocol {
                    out.append("\(inner)var \(p.name): \(p.type) { get }")
                } else {
                    var line = inner
                    if let w = p.wrapper { line += w + " " }
                    if p.isStatic { line += "static " }
                    let keyword = (p.wrapper == nil && t.kind != .class && !p.isStatic && !p.type.hasSuffix("?")) ? "let" : "var"
                    line += "\(keyword) \(p.name): \(p.type)"
                    if p.isStatic { line += " = \(p.type)()" }
                    if p.wrapper == "@State" { line += defaultValue(for: p.type).map { " = \($0)" } ?? "" }
                    out.append(line)
                }
            }
            if !t.props.isEmpty && !t.funcs.isEmpty { out.append("") }
            for (i, f) in t.funcs.enumerated() {
                if i > 0 { out.append("") }
                if t.kind == .protocol {
                    out.append("\(inner)func \(f.signature)")
                } else {
                    if t.tags.contains("test") { out.append("\(inner)@Test") }
                    out.append(contentsOf: render(func: f, indent: inner))
                }
            }
            out.append(indent + "}")
            return out
        }

        private static func render(func f: FuncSpec, indent: String) -> [String] {
            var out: [String] = []
            let isStatic = f.signature.hasPrefix("static ")
            let signature = isStatic ? String(f.signature.dropFirst(7)) : f.signature
            out.append("\(indent)\(isStatic ? "static " : "")func \(signature) {")
            let body = f.body.isEmpty ? defaultBody(for: f) : f.body
            for line in body { out.append(indent + "    " + line) }
            out.append(indent + "}")
            return out
        }

        private static func computedBody(for p: PropSpec, type t: TypeSpec) -> [String] {
            if p.type == "some Scene" {
                return ["WindowGroup {", "    NotesListView()", "        .environment(environment)", "}"]
            }
            if p.type == "some View" {
                switch t.name {
                case "NotesListView": return ["List(viewModel.notes) { note in", "    NoteRowView(note: note)", "}", ".task { await viewModel.load() }"]
                case "NoteRowView": return ["VStack(alignment: .leading) {", "    Text(note.title).font(Typography.title)", "    Text(note.excerpt(maxLength: 60)).font(Typography.caption)", "}"]
                case "TagChipView": return ["Text(tag.name)", "    .padding(.horizontal, 8)", "    .background(isSelected ? OrbitTheme.standard.accent : .clear, in: Capsule())"]
                default: return ["VStack {", "    Text(\"\(t.name)\")", "}"]
                }
            }
            return ["fatalError(\"unreachable\")"]
        }

        private static func defaultBody(for f: FuncSpec) -> [String] {
            guard let ret = f.returnType else { return ["// \(f.name) implementation"] }
            return [defaultValue(for: ret) ?? "\(ret)()"]
        }

        private static func defaultValue(for type: String) -> String? {
            if type.hasSuffix("?") { return "nil" }
            if type.hasPrefix("[") { return "[]" }
            switch type {
            case "Bool": return "false"
            case "String": return "\"\""
            case "Int", "Double", "CGFloat": return "0"
            case "Date": return ".now"
            case "some View": return "EmptyView()"
            default: return nil
            }
        }
    }
}
