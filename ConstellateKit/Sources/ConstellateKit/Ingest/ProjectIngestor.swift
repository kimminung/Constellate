import Foundation

/// Options for walking a project folder.
public struct IngestOptions: Hashable, Codable, Sendable {
    /// File extensions (lower-case, no dot) to include as code files.
    public var includedExtensions: Set<String> = ["swift", "m", "mm", "h", "c", "cpp", "py", "js", "ts", "tsx", "jsx", "kt", "java", "go", "rs", "rb", "cs", "metal", "sh", "md", "json", "yml", "yaml", "plist"]
    /// Directory names skipped entirely.
    public var excludedDirectoryNames: Set<String> = [".git", ".build", "build", "DerivedData", "Pods", "node_modules", ".swiftpm", "xcuserdata", ".venv", "venv", "__pycache__", "dist", ".idea"]
    /// Skip files bigger than this (bytes).
    public var maxFileSize: Int = 1_500_000
    /// Hard cap on file nodes so huge repos stay interactive.
    public var maxFiles: Int = 4000
    /// Extract symbols (types / functions / imports) for these languages.
    public var symbolLanguages: Set<String> = ["swift"]

    public init() {}
}

public enum IngestError: Error, Sendable, LocalizedError {
    case notADirectory(URL)
    case unreadable(URL)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notADirectory(let url): "\(url.lastPathComponent) is not a folder."
        case .unreadable(let url): "Could not read \(url.lastPathComponent)."
        case .cancelled: "Ingest cancelled."
        }
    }
}

/// Progress reported while walking a project.
public struct IngestProgress: Sendable, Hashable {
    public var filesSeen: Int
    public var filesParsed: Int
    public var currentPath: String
    public init(filesSeen: Int, filesParsed: Int, currentPath: String) {
        self.filesSeen = filesSeen
        self.filesParsed = filesParsed
        self.currentPath = currentPath
    }
}

/// Walks a folder and builds a `CodeGraph`: module → folders → files → (Swift) types → members,
/// plus imports / inherits / references edges from `SwiftSymbolExtractor`.
///
/// Node identifiers: the module is the root folder's name; folders and files use
/// `"<module>/<relative path>"`; symbols use `"<file id>#Type"`, `"<file id>#Type.member"`
/// (functions get a trailing `()`), and top-level functions `"<file id>#name()"`.
///
/// Edges:
/// - `contains` for the whole tree,
/// - `imports` from a file to the top-level folder (or root) with the imported module's name;
///   external imports become the file tag `imports:<Module>`,
/// - `inherits` from a type to a type declared in the project (duplicates prefer the same folder);
///   unresolved supertypes become the type tag `inherits:<Name>`,
/// - `references` from a file to project types it mentions (other files only).
///
/// The caller is responsible for security-scoped access to `rootURL` (start/stop accessing).
/// The walk runs on the cooperative thread pool (this type is not actor-isolated) and honours task cancellation.
public struct ProjectIngestor: Sendable {
    public var options: IngestOptions

    /// Package / bundle directory extensions that are never descended into.
    public static let bundleExtensions: Set<String> = [
        "xcodeproj", "xcworkspace", "xcassets", "app", "framework", "bundle", "xcdatamodeld", "playground",
        "appex", "dSYM", "xctest", "docc", "lproj", "scnassets", "rkassets", "xcarchive", "swiftpm"
    ]

    public init(options: IngestOptions = IngestOptions()) {
        self.options = options
    }

    public func ingest(rootURL: URL, progress: (@Sendable (IngestProgress) -> Void)? = nil) async throws -> CodeGraph {
        // `ingest` is a nonisolated async function, so it already executes off the caller's actor.
        if Task.isCancelled { throw IngestError.cancelled }
        return try Walker(rootURL: rootURL, options: options, progress: progress).run()
    }

    /// Infers an architecture layer from a relative path and (optionally) extracted tags.
    public static func inferLayer(path: String, tags: Set<String> = []) -> ArchitectureLayer {
        let p = path.lowercased()
        if tags.contains("test") || isTestPath(p) { return .test }
        if tags.contains("SwiftUI.View") || tags.contains("SwiftUI.App") || tags.contains("entry-point") || p.contains("view") || p.contains("/ui/") || p.contains("screen") || p.contains("scene") { return .presentation }
        if p.contains("repository") || p.contains("network") || p.contains("persistence") || p.contains("storage") || p.contains("api") || p.contains("database") { return .data }
        if p.contains("model") || p.contains("domain") || p.contains("usecase") || p.contains("service") || p.contains("engine") { return .domain }
        if p.contains("util") || p.contains("extension") || p.contains("helper") || p.contains("config") || p.contains("support") { return .infrastructure }
        return .unknown
    }

    /// True when a path component is a test folder / file (`Tests`, `UnitTests`, `FooTests.swift`, `TestSupport`, `__tests__`).
    /// Matches whole components so names like `NoteStore` ("no-test-ore") are not mistaken for tests.
    static func isTestPath(_ lowercasedPath: String) -> Bool {
        for component in lowercasedPath.split(separator: "/") {
            var base = String(component)
            if let dot = base.lastIndex(of: ".") { base = String(base[..<dot]) }
            base = base.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            if base == "test" || base == "tests" || base.hasSuffix("tests") || base.hasSuffix("test") || base.hasPrefix("test") {
                return true
            }
        }
        return false
    }

    // MARK: - Walker

    private struct IncludedFile {
        var url: URL
        /// Path components relative to the root (last one is the file name).
        var components: [String]
        var size: Int
        var modifiedAt: Date?
    }

    private struct Walker {
        let rootURL: URL
        let options: IngestOptions
        let progress: (@Sendable (IngestProgress) -> Void)?
        let extractor = SwiftSymbolExtractor()

        func run() throws -> CodeGraph {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
                throw IngestError.notADirectory(rootURL)
            }

            let files = try collectFiles(fm: fm)
            let moduleName = rootURL.lastPathComponent
            var builder = GraphAssembler(moduleName: moduleName, options: options)

            var parsed = 0
            for (index, file) in files.enumerated() {
                if Task.isCancelled { throw IngestError.cancelled }
                let relative = file.components.joined(separator: "/")
                let ext = (file.components.last as NSString?)?.pathExtension.lowercased() ?? ""
                let language = ProjectIngestor.language(forExtension: ext)

                var extracted: ExtractedFile? = nil
                var lineCount = 0
                let rolePath = moduleName + "/" + relative
                var role: CodeRole
                if let language, options.symbolLanguages.contains(language),
                   let source = ProjectIngestor.readSource(at: file.url) {
                    let e = extractor.extract(source: source)
                    extracted = e
                    lineCount = e.lineCount
                    parsed += 1
                    role = RelationClassifier.inferRole(path: rolePath, language: language, source: source, symbols: e.symbols)
                } else {
                    lineCount = ProjectIngestor.countLines(at: file.url)
                    role = RelationClassifier.inferRole(path: rolePath, language: language ?? ext, source: nil)
                }
                builder.addFile(components: file.components, language: language ?? ext, lineCount: lineCount, modifiedAt: file.modifiedAt, extracted: extracted, role: role)

                if (index + 1) % 25 == 0 {
                    progress?(IngestProgress(filesSeen: index + 1, filesParsed: parsed, currentPath: relative))
                }
            }
            progress?(IngestProgress(filesSeen: files.count, filesParsed: parsed, currentPath: ""))
            if Task.isCancelled { throw IngestError.cancelled }
            return builder.finish()
        }

        private func collectFiles(fm: FileManager) throws -> [IncludedFile] {
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .isPackageKey]
            let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
            let rootComponents = resolvedRoot.pathComponents
            guard let enumerator = fm.enumerator(at: resolvedRoot, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                throw IngestError.unreadable(rootURL)
            }

            var files: [IncludedFile] = []
            var seen = 0
            for case let url as URL in enumerator {
                if seen % 200 == 0, Task.isCancelled { throw IngestError.cancelled }
                seen += 1
                let values = try? url.resourceValues(forKeys: keys)
                let name = url.lastPathComponent
                let ext = url.pathExtension.lowercased()
                if values?.isDirectory == true {
                    if name.hasPrefix(".") || options.excludedDirectoryNames.contains(name) || ProjectIngestor.bundleExtensions.contains(ext) || values?.isPackage == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard values?.isRegularFile == true else { continue }
                if name.hasPrefix(".") { continue }
                guard options.includedExtensions.contains(ext) else { continue }
                let size = values?.fileSize ?? 0
                if size > options.maxFileSize { continue }

                let standardized = url.resolvingSymlinksInPath().standardizedFileURL
                var components = Array(standardized.pathComponents.dropFirst(rootComponents.count))
                if components.isEmpty { components = [name] }
                // Any ancestor named like an excluded directory (defensive; enumerator already skips them).
                if components.dropLast().contains(where: { options.excludedDirectoryNames.contains($0) || $0.hasPrefix(".") }) { continue }
                files.append(IncludedFile(url: url, components: components, size: size, modifiedAt: values?.contentModificationDate))
                if files.count >= options.maxFiles { break }
            }
            files.sort { $0.components.joined(separator: "/") < $1.components.joined(separator: "/") }
            return files
        }
    }

    // MARK: - Assembler

    /// Accumulates nodes / edges and resolves cross-file relations at the end.
    private struct GraphAssembler {
        let moduleName: String
        let options: IngestOptions

        private var nodes: [CodeNode] = []
        private var nodeIDs: Set<NodeID> = []
        private var folderIDs: Set<NodeID> = []
        private var edges: [CodeEdge] = []
        private var edgeSet: Set<CodeEdge> = []

        /// type name → ids of type nodes with that name
        private var typesByName: [String: [NodeID]] = [:]
        /// Pending relations resolved in `finish()`.
        private var pendingImports: [(file: NodeID, module: String)] = []
        private var pendingInherits: [(type: NodeID, superName: String)] = []
        private var pendingReferences: [(file: NodeID, typeName: String, fact: ReferenceFact)] = []
        /// `extension Foo` declarations → `extends` edges to `Foo` when it is declared in another file.
        private var pendingExtends: [(extensionNode: NodeID, typeName: String)] = []
        /// NotificationCenter names → posting / observing files (`notifies` edges).
        private var notificationPosters: [String: Set<NodeID>] = [:]
        private var notificationObservers: [String: Set<NodeID>] = [:]
        /// Role per file / type node (target roles decide composes vs creates).
        private var roles: [NodeID: CodeRole] = [:]
        /// Newest modification date per folder (propagated upward).
        private var folderDates: [NodeID: Date] = [:]

        init(moduleName: String, options: IngestOptions) {
            self.moduleName = moduleName
            self.options = options
            let root = CodeNode(id: NodeID(moduleName), name: moduleName, kind: .module, path: moduleName)
            append(root)
        }

        private mutating func append(_ node: CodeNode) {
            nodes.append(node)
            nodeIDs.insert(node.id)
            if let p = node.parent { addEdge(CodeEdge(from: p, to: node.id, kind: .contains)) }
        }

        private mutating func addEdge(_ edge: CodeEdge) {
            if edgeSet.insert(edge).inserted { edges.append(edge) }
        }

        private mutating func uniqueID(_ base: String) -> NodeID {
            var id = NodeID(base)
            var n = 2
            while nodeIDs.contains(id) {
                id = NodeID("\(base)#\(n)")
                n += 1
            }
            return id
        }

        mutating func addFile(components: [String], language: String, lineCount: Int, modifiedAt: Date?, extracted: ExtractedFile?, role: CodeRole? = nil) {
            // Folders
            var parentID = NodeID(moduleName)
            var pathSoFar = moduleName
            for dir in components.dropLast() {
                pathSoFar += "/" + dir
                let id = NodeID(pathSoFar)
                if !nodeIDs.contains(id) {
                    append(CodeNode(id: id, name: dir, kind: .folder, path: pathSoFar, parent: parentID, layer: ProjectIngestor.inferLayer(path: pathSoFar)))
                    folderIDs.insert(id)
                }
                if let modifiedAt {
                    if let existing = folderDates[id] { folderDates[id] = max(existing, modifiedAt) } else { folderDates[id] = modifiedAt }
                }
                parentID = id
            }
            if let modifiedAt {
                let rootID = NodeID(moduleName)
                if let existing = folderDates[rootID] { folderDates[rootID] = max(existing, modifiedAt) } else { folderDates[rootID] = modifiedAt }
            }

            // File
            let fileName = components.last ?? ""
            let filePath = pathSoFar + "/" + fileName
            let fileID = NodeID(filePath)
            var fileTags = extracted?.tags ?? []
            let baseName = (fileName as NSString).deletingPathExtension
            if baseName.hasSuffix("Tests") || baseName.hasSuffix("Test") { fileTags.insert("test") }
            let relativePath = components.joined(separator: "/")
            let fileRole = role ?? RelationClassifier.inferRole(path: filePath, language: language, source: nil)
            let fileNode = CodeNode(
                id: fileID, name: fileName, kind: .file, path: filePath, parent: parentID, language: language,
                lines: lineCount > 0 ? LineRange(start: 1, end: lineCount) : nil, lineCount: lineCount, modifiedAt: modifiedAt,
                layer: ProjectIngestor.inferLayer(path: relativePath, tags: fileTags), tags: fileTags, role: fileRole
            )
            append(fileNode)
            roles[fileID] = fileRole
            guard let extracted else { return }

            for module in extracted.imports { pendingImports.append((fileID, module)) }
            for name in extracted.referencedTypeNames.sorted() {
                pendingReferences.append((fileID, name, extracted.referenceFacts[name] ?? .mentions))
            }
            for name in extracted.postedNotifications { notificationPosters[name, default: []].insert(fileID) }
            for name in extracted.observedNotifications { notificationObservers[name, default: []].insert(fileID) }

            // Symbols: types / extensions first (they may be parents), then members.
            var typeIDByName: [String: NodeID] = [:]
            var extensionCount: [String: Int] = [:]
            let fileLayer = fileNode.layer

            func symbolLayer(_ tags: Set<String>) -> ArchitectureLayer {
                tags.contains("SwiftUI.View") ? .presentation : (fileLayer == .test || tags.contains("test") ? .test : ProjectIngestor.inferLayer(path: relativePath, tags: tags))
            }

            // Pass 1: containers in source order so nesting resolves (outer declared before inner).
            for symbol in extracted.symbols where symbol.nodeKind.isSpatial {
                let parentNode = symbol.parentName.flatMap { typeIDByName[$0] } ?? fileID
                let qualified: String
                if let pn = symbol.parentName, typeIDByName[pn] != nil, let parentRaw = typeIDByName[pn]?.raw, let hash = parentRaw.firstIndex(of: "#") {
                    qualified = String(parentRaw[parentRaw.index(after: hash)...]) + "." + symbol.name
                } else {
                    qualified = symbol.name
                }
                let base: String
                if symbol.kind == .extension {
                    let n = (extensionCount[qualified] ?? 0) + 1
                    extensionCount[qualified] = n
                    base = "\(filePath)#\(qualified)(ext\(n == 1 ? "" : String(n)))"
                } else {
                    base = "\(filePath)#\(qualified)"
                }
                let id = uniqueID(base)
                var tags = symbol.tags
                if fileTags.contains("test") && symbol.kind != .extension { tags.insert("test") }
                let typeRole = RelationClassifier.role(forType: tags, kind: symbol.kind, fileRole: fileRole)
                let node = CodeNode(
                    id: id, name: symbol.name, kind: symbol.nodeKind, path: filePath, parent: parentNode, language: language,
                    lines: symbol.lines, lineCount: symbol.lines.count, modifiedAt: modifiedAt, layer: symbolLayer(tags), tags: tags,
                    role: typeRole
                )
                append(node)
                roles[id] = typeRole
                // Types always own their name; extensions only register it when no type of that name is in the file.
                // Members of `extension Foo` therefore attach to `Foo` when it is declared here, otherwise to the extension.
                let extendsLocalType = symbol.kind == .extension && typeIDByName[symbol.name] != nil
                if symbol.kind != .extension || typeIDByName[symbol.name] == nil {
                    typeIDByName[symbol.name] = id
                }
                if symbol.kind != .extension {
                    typesByName[symbol.name, default: []].append(id)
                    for superName in symbol.inherits { pendingInherits.append((id, superName)) }
                } else {
                    // `extension Foo: Bar` adds conformances; `extension Foo` of a type declared elsewhere is an `extends` edge.
                    for superName in symbol.inherits { pendingInherits.append((id, superName)) }
                    if !extendsLocalType {
                        let base = symbol.name.split(separator: ".").last.map(String.init) ?? symbol.name
                        pendingExtends.append((id, base))
                    }
                }
            }

            // Pass 2: members.
            for symbol in extracted.symbols where !symbol.nodeKind.isSpatial {
                let parentID = symbol.parentName.flatMap { typeIDByName[$0] } ?? fileID
                let suffix = symbol.kind == .function ? "()" : ""
                let base: String
                if let parentRaw = symbol.parentName.flatMap({ typeIDByName[$0]?.raw }), let hash = parentRaw.firstIndex(of: "#") {
                    base = "\(filePath)#\(parentRaw[parentRaw.index(after: hash)...]).\(symbol.name)\(suffix)"
                } else {
                    base = "\(filePath)#\(symbol.name)\(suffix)"
                }
                let id = uniqueID(base)
                let node = CodeNode(
                    id: id, name: symbol.name, kind: symbol.nodeKind, path: filePath, parent: parentID, language: language,
                    lines: symbol.lines, lineCount: symbol.lines.count, modifiedAt: modifiedAt, layer: symbolLayer(symbol.tags), tags: symbol.tags
                )
                append(node)
            }
        }

        mutating func finish() -> CodeGraph {
            // Folder dates
            for (i, n) in nodes.enumerated() where n.kind == .folder || n.kind == .module {
                if let d = folderDates[n.id] { nodes[i].modifiedAt = d }
            }

            // Imports: resolve against top-level folders and the root.
            let rootID = NodeID(moduleName)
            var topLevel: [String: NodeID] = [moduleName: rootID]
            for n in nodes where n.kind == .folder && n.parent == rootID { topLevel[n.name] = n.id }
            var fileTagAdditions: [NodeID: Set<String>] = [:]
            for (file, module) in pendingImports {
                if let target = topLevel[module], target != file {
                    addEdge(CodeEdge(from: file, to: target, kind: .imports, relation: .imports))
                } else {
                    fileTagAdditions[file, default: []].insert("imports:\(module)")
                }
            }

            // Inherits: prefer a type declared in the same folder. Delegate / DataSource supertypes are `delegates`.
            var folderOf: [NodeID: String] = [:]
            var pathOf: [NodeID: String] = [:]
            for n in nodes where n.kind == .type || n.kind == .extensionDecl {
                folderOf[n.id] = (n.path as NSString).deletingLastPathComponent
                pathOf[n.id] = n.path
            }
            /// file id → types it already inherits from / extends (those names are not also drawn as plain references).
            var typeLinkedTargets: [NodeID: Set<NodeID>] = [:]
            for (type, superName) in pendingInherits {
                if let target = resolveType(named: superName, near: folderOf[type], excluding: type) {
                    addEdge(CodeEdge(from: type, to: target, kind: .inherits, relation: RelationClassifier.inheritanceRelation(superName: superName)))
                    if let path = pathOf[type] { typeLinkedTargets[NodeID(path), default: []].insert(target) }
                } else {
                    fileTagAdditions[type, default: []].insert("inherits:\(superName)")
                }
            }
            // Extends: `extension Foo` → `Foo` declared in another file.
            for (ext, typeName) in pendingExtends {
                guard let target = resolveType(named: typeName, near: folderOf[ext], excluding: ext), pathOf[target] != pathOf[ext] else { continue }
                addEdge(CodeEdge(from: ext, to: target, kind: .inherits, relation: .extends))
                if let path = pathOf[ext] { typeLinkedTargets[NodeID(path), default: []].insert(target) }
            }

            // References: file → type in another file, classified (binds / presents / composes / creates / uses).
            var fileOfNode: [NodeID: String] = [:]
            for n in nodes where n.kind == .type { fileOfNode[n.id] = n.path }
            for (file, typeName, fact) in pendingReferences {
                guard let target = resolveType(named: typeName, near: (file.raw as NSString).deletingLastPathComponent, excluding: nil) else { continue }
                if fileOfNode[target] == file.raw { continue }
                if typeLinkedTargets[file]?.contains(target) == true { continue }
                let relation = RelationClassifier.relation(for: fact, sourceRole: roles[file], targetRole: roles[target])
                addEdge(CodeEdge(from: file, to: target, kind: .references, weight: 1, relation: relation))
            }

            // Notifications: every poster → every observer of the same name (runtime coupling, kind `.calls`).
            for name in notificationPosters.keys.sorted() {
                guard let observers = notificationObservers[name] else { continue }
                for poster in notificationPosters[name, default: []].sorted(by: { $0.raw < $1.raw }) {
                    for observer in observers.sorted(by: { $0.raw < $1.raw }) where observer != poster {
                        addEdge(CodeEdge(from: poster, to: observer, kind: .calls, relation: .notifies))
                    }
                }
            }

            for (i, n) in nodes.enumerated() {
                if let extra = fileTagAdditions[n.id] { nodes[i].tags.formUnion(extra) }
            }
            return CodeGraph(projectName: moduleName, rootID: rootID, nodes: nodes, edges: edges)
        }

        private func resolveType(named name: String, near folder: String?, excluding: NodeID?) -> NodeID? {
            guard let candidates = typesByName[name], !candidates.isEmpty else { return nil }
            let filtered = candidates.filter { $0 != excluding }
            guard !filtered.isEmpty else { return nil }
            if filtered.count == 1 { return filtered[0] }
            if let folder {
                if let same = filtered.first(where: { ($0.raw as NSString).deletingLastPathComponent.hasPrefix(folder) }) { return same }
            }
            return filtered[0]
        }
    }

    // MARK: - File helpers

    static func language(forExtension ext: String) -> String? {
        switch ext {
        case "swift": "swift"
        case "m", "mm", "h": "objc"
        case "c": "c"
        case "cpp", "cc", "cxx", "hpp": "cpp"
        case "py": "python"
        case "js", "jsx": "javascript"
        case "ts", "tsx": "typescript"
        case "kt": "kotlin"
        case "java": "java"
        case "go": "go"
        case "rs": "rust"
        case "rb": "ruby"
        case "cs": "csharp"
        case "metal": "metal"
        case "sh": "shell"
        case "md": "markdown"
        case "json": "json"
        case "yml", "yaml": "yaml"
        case "plist": "plist"
        default: nil
        }
    }

    static func readSource(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .isoLatin1)
    }

    /// Counts lines without decoding text: newline bytes plus one for an unterminated last line.
    static func countLines(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), !data.isEmpty else { return 0 }
        var count = 0
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for b in buf where b == 10 { count += 1 }
        }
        if data.last != 10 { count += 1 }
        return count
    }
}
