import Foundation

public struct CodeSearchHit: Hashable, Sendable, Identifiable {
    public var id: NodeID { nodeID }
    public var nodeID: NodeID
    public var score: Double
    /// Human-readable reason ("name matches", "SwiftUI view with @State", …).
    public var reason: String

    public init(nodeID: NodeID, score: Double, reason: String) {
        self.nodeID = nodeID
        self.score = score
        self.reason = reason
    }
}

/// Natural-language-ish structural search over a `CodeGraph`. Used directly for typed queries and as
/// the fallback / grounding step for the host AI's voice "find the code that …" requests.
///
/// Understands: fuzzy names and paths, kind words (view, model, test, protocol, actor, extension, enum,
/// function, folder, file), tag phrases (`@State`, `@Observable`, `async`, `SwiftUI`, `@main` / entry point),
/// structural phrases ("inherits X", "conforms to X", "imports Y", "uses Z", "in folder F"), relation phrases
/// ("presents X", "observed by X", "creates X", "embedded in X", "X를 띄우는"), and Korean
/// equivalents (뷰, 모델, 테스트, 프로토콜, 액터, 익스텐션, 열거형, 함수, 폴더, 파일, 상속, 임포트, 사용하는, 진입점).
///
/// Scoring: name exact 10 · prefix 6 · substring 4 · camel-case initials 5 · fuzzy (Levenshtein ≤ 2) 3 ·
/// path substring 2 · each structural constraint +5 · each tag +4 · kind match +3. Tag and structural
/// constraints are hard filters; a kind word drops nodes of other kinds.
public struct CodeSearcher: Sendable {
    public init() {}

    public func search(_ query: String, in graph: CodeGraph, limit: Int = 12) -> [CodeSearchHit] {
        var parsed = ParsedQuery(query)
        parsed.resolveRelations(in: graph)
        guard parsed.hasCriteria else { return [] }

        var hits: [CodeSearchHit] = []
        for node in graph.nodes {
            guard let hit = score(node, parsed: parsed, graph: graph) else { continue }
            hits.append(hit)
        }
        hits.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            let an = graph.node(a.nodeID), bn = graph.node(b.nodeID)
            if let ak = an?.kind.order, let bk = bn?.kind.order, ak != bk { return ak < bk }
            return (an?.name ?? "") < (bn?.name ?? "")
        }
        return Array(hits.prefix(max(0, limit)))
    }

    /// Describes how `query` was understood (kind, tags, structural constraints, free text).
    /// Shown in the AI bubble so people can see why results came back.
    public func explainQuery(_ query: String, in graph: CodeGraph? = nil) -> String {
        var p = ParsedQuery(query)
        if let graph { p.resolveRelations(in: graph) }
        var parts: [String] = []
        if let kind = p.kind { parts.append("kind = \(kind.label)") }
        if !p.tags.isEmpty { parts.append("tags: " + p.tags.sorted().joined(separator: ", ")) }
        for c in p.constraints { parts.append(c.description) }
        if !p.freeTokens.isEmpty { parts.append("name/path contains: " + p.freeTokens.joined(separator: ", ")) }
        if parts.isEmpty { return "No searchable criteria found in \"\(query)\"." }
        return "Looking for " + parts.joined(separator: "; ") + "."
    }

    // MARK: - Query model

    enum KindWord: Sendable {
        case view, model, test, protocolType, actor, extensionType, enumType, structType, classType, function, property, folder, file, type

        var label: String {
            switch self {
            case .view: "SwiftUI view"
            case .model: "model type"
            case .test: "test"
            case .protocolType: "protocol"
            case .actor: "actor"
            case .extensionType: "extension"
            case .enumType: "enum"
            case .structType: "struct"
            case .classType: "class"
            case .function: "function"
            case .property: "property"
            case .folder: "folder"
            case .file: "file"
            case .type: "type"
            }
        }

        static func from(_ token: String) -> KindWord? {
            switch token {
            case "view", "views", "뷰", "화면", "screen", "screens": .view
            case "model", "models", "모델", "entity", "entities", "엔티티": .model
            case "test", "tests", "테스트", "spec", "specs": .test
            case "protocol", "protocols", "프로토콜": .protocolType
            case "actor", "actors", "액터": .actor
            case "extension", "extensions", "익스텐션", "확장": .extensionType
            case "enum", "enums", "열거형", "이넘": .enumType
            case "struct", "structs", "구조체": .structType
            case "class", "classes", "클래스": .classType
            case "function", "functions", "func", "funcs", "method", "methods", "함수", "메서드": .function
            case "property", "properties", "프로퍼티", "속성": .property
            case "folder", "folders", "directory", "directories", "폴더", "디렉터리": .folder
            case "file", "files", "파일": .file
            case "type", "types", "타입": .type
            default: nil
            }
        }
    }

    enum Constraint: Hashable, Sendable, CustomStringConvertible {
        case inherits(String)
        case imports(String)
        case references(String)
        case inFolder(String)
        /// A classified relation (`RelationKind`) to (`outgoing`) or from a node named `name` —
        /// "presents SettingsView", "observed by NoteListView", "SettingsView를 띄우는".
        case related(RelationKind, outgoing: Bool, String)

        var description: String {
            switch self {
            case .inherits(let n): "inherits/conforms to \(n)"
            case .imports(let n): "imports \(n)"
            case .references(let n): "uses \(n)"
            case .inFolder(let n): "inside folder \(n)"
            case .related(let kind, let outgoing, let n):
                "\(kind.phrase(outgoing: outgoing).components(separatedBy: " · ").first ?? kind.rawValue) \(n)"
            }
        }
    }

    /// Relation verbs understood in queries: active forms take the object after them ("presents X"), Korean
    /// forms take it before ("X를 띄우는"); passive forms take "by / in / from X" ("presented by X").
    static let activeRelationVerbs: [String: RelationKind] = [
        "presents": .presents, "present": .presents, "presenting": .presents, "navigates": .presents, "navigate": .presents,
        "observes": .binds, "observe": .binds, "observing": .binds, "binds": .binds, "bind": .binds, "watches": .binds,
        "creates": .creates, "create": .creates, "creating": .creates, "instantiates": .creates, "instantiate": .creates,
        "embeds": .composes, "embed": .composes, "embedding": .composes, "composes": .composes, "compose": .composes,
        "delegates": .delegates
    ]
    static let passiveRelationVerbs: [String: RelationKind] = [
        "presented": .presents, "observed": .binds, "bound": .binds, "created": .creates, "instantiated": .creates,
        "embedded": .composes, "composed": .composes, "notified": .notifies
    ]
    static let koreanRelationVerbs: [String: RelationKind] = [
        "띄우는": .presents, "띄우기": .presents, "여는": .presents, "이동하는": .presents, "전환하는": .presents,
        "관찰하는": .binds, "구독하는": .binds, "바인딩하는": .binds,
        "생성하는": .creates, "만드는": .creates,
        "포함하는": .composes, "품는": .composes
    ]

    struct ParsedQuery: Sendable {
        var kind: KindWord?
        var tags: Set<String> = []
        var constraints: [Constraint] = []
        /// Lower-cased free-text tokens.
        var freeTokens: [String] = []

        var hasCriteria: Bool { kind != nil || !tags.isEmpty || !constraints.isEmpty || !freeTokens.isEmpty }

        /// A relation phrase only constrains when its object names something in the graph ("presents SettingsView");
        /// otherwise ("creates notes") the object goes back to free text, so ordinary sentences keep matching names.
        mutating func resolveRelations(in graph: CodeGraph) {
            guard constraints.contains(where: { if case .related = $0 { return true } else { return false } }) else { return }
            var known: Set<String> = []
            for node in graph.nodes {
                let n = node.name.lowercased()
                known.insert(n)
                if n.hasSuffix(".swift") { known.insert(String(n.dropLast(6))) }
            }
            var kept: [Constraint] = []
            for c in constraints {
                if case .related(_, _, let name) = c, !known.contains(name.lowercased()) {
                    freeTokens.append(name.lowercased())
                } else {
                    kept.append(c)
                }
            }
            constraints = kept
        }

        static let stopWords: Set<String> = [
            "the", "a", "an", "that", "which", "who", "with", "and", "or", "of", "to", "me", "all", "any", "some",
            "find", "show", "search", "locate", "look", "for", "please", "where", "is", "are", "has", "have", "using",
            "what", "whats", "list", "give", "get", "every", "those", "these", "it", "its",
            "찾아", "찾아줘", "찾기", "보여줘", "보여", "알려줘", "쓰는", "사용하는", "있는", "하는", "되는", "안의", "안에",
            "모든", "전부", "좀", "것", "거", "들", "및", "그리고", "또는", "중", "중에서", "어디", "뭐", "무엇", "어떤",
            "코드", "code"
        ]

        private static let koreanParticles = ["에서", "으로", "에게", "부터", "까지", "처럼", "를", "을", "이", "가", "은", "는", "의", "에", "로", "와", "과", "도", "만"]

        init(_ query: String) {
            // Tokenise: keep @, ., _ inside tokens; split on whitespace and other punctuation.
            var rawTokens: [String] = []
            var current = ""
            for ch in query {
                if ch.isLetter || ch.isNumber || ch == "@" || ch == "_" || ch == "." {
                    current.append(ch)
                } else {
                    if !current.isEmpty { rawTokens.append(current); current = "" }
                }
            }
            if !current.isEmpty { rawTokens.append(current) }
            let tokens = rawTokens.map(ParsedQuery.stripParticles).filter { !$0.isEmpty }
            let lower = tokens.map { $0.lowercased() }

            var consumed = Array(repeating: false, count: tokens.count)

            // Structural phrases.
            for i in tokens.indices where !consumed[i] {
                let t = lower[i]
                func next(_ k: Int) -> Int? {
                    let j = i + k
                    return j < tokens.count && !consumed[j] ? j : nil
                }
                func prev() -> Int? {
                    let j = i - 1
                    return j >= 0 && !consumed[j] ? j : nil
                }
                switch t {
                case "inherits", "inherit", "subclass", "subclasses", "extends", "conforms", "conforming", "implements", "adopts":
                    var j = next(1)
                    if let jj = j, ["from", "to", "of"].contains(lower[jj]) { j = next(2) }
                    if let j, let name = ParsedQuery.identifier(tokens[j]) {
                        constraints.append(.inherits(name)); consumed[i] = true; consumed[j] = true
                    }
                case "상속", "상속하는", "상속받는", "상속받은", "채택", "채택하는", "준수", "준수하는", "따르는":
                    if let p = prev(), let name = ParsedQuery.identifier(tokens[p]) {
                        constraints.append(.inherits(name)); consumed[i] = true; consumed[p] = true
                    }
                case "imports", "import", "importing":
                    if let j = next(1), let name = ParsedQuery.identifier(tokens[j]) {
                        constraints.append(.imports(name)); consumed[i] = true; consumed[j] = true
                    }
                case "임포트", "임포트하는", "임포트한", "불러오는", "가져오는":
                    if let p = prev(), let name = ParsedQuery.identifier(tokens[p]) {
                        constraints.append(.imports(name)); consumed[i] = true; consumed[p] = true
                    }
                case "uses", "use", "references", "referencing", "reference", "calls", "calling", "depends", "depending":
                    var j = next(1)
                    if let jj = j, ["on"].contains(lower[jj]) { j = next(2) }
                    if let j, let name = ParsedQuery.identifier(tokens[j]) {
                        constraints.append(.references(name)); consumed[i] = true; consumed[j] = true
                    }
                case "사용", "참조", "참조하는", "호출", "호출하는", "의존", "의존하는":
                    if let p = prev(), let name = ParsedQuery.identifier(tokens[p]) {
                        constraints.append(.references(name)); consumed[i] = true; consumed[p] = true
                    }
                case _ where CodeSearcher.activeRelationVerbs[t] != nil:
                    // "presents X", "navigates to X", "delegates to X"
                    var j = next(1)
                    if let jj = j, ["to", "into"].contains(lower[jj]) { j = next(2) }
                    if let j, let name = ParsedQuery.identifier(tokens[j]), KindWord.from(lower[j]) == nil, let kind = CodeSearcher.activeRelationVerbs[t] {
                        constraints.append(.related(kind, outgoing: true, name)); consumed[i] = true; consumed[j] = true
                        if j == i + 2 { consumed[i + 1] = true }
                    }
                case _ where CodeSearcher.passiveRelationVerbs[t] != nil:
                    // "presented by X", "embedded in X", "notified from X"
                    if let j = next(1), ["by", "in", "from", "into"].contains(lower[j]), let k = next(2),
                       let name = ParsedQuery.identifier(tokens[k]), let kind = CodeSearcher.passiveRelationVerbs[t] {
                        constraints.append(.related(kind, outgoing: false, name)); consumed[i] = true; consumed[j] = true; consumed[k] = true
                    }
                case _ where CodeSearcher.koreanRelationVerbs[t] != nil:
                    if let p = prev(), let name = ParsedQuery.identifier(tokens[p]), let kind = CodeSearcher.koreanRelationVerbs[t] {
                        constraints.append(.related(kind, outgoing: true, name)); consumed[i] = true; consumed[p] = true
                    }
                case "in", "inside", "under", "within":
                    // "in folder F" / "in F" / "inside F folder"
                    guard var j = next(1) else { break }
                    var usedFolderWord = false
                    if ["folder", "directory", "dir", "폴더"].contains(lower[j]) {
                        guard let jj = next(2) else { break }
                        j = jj
                        usedFolderWord = true
                    }
                    if let name = ParsedQuery.identifier(tokens[j]), KindWord.from(lower[j]) == nil, !ParsedQuery.stopWords.contains(lower[j]) {
                        constraints.append(.inFolder(name)); consumed[i] = true; consumed[j] = true
                        if usedFolderWord {
                            consumed[i + 1] = true
                        } else if j + 1 < tokens.count, ["folder", "directory", "폴더"].contains(lower[j + 1]) {
                            consumed[j + 1] = true
                        }
                    }
                case "folder", "directory", "폴더", "디렉터리":
                    // "F folder" / "folder F" with a Latin identifier that isn't itself a kind word.
                    if let p = prev(), let name = ParsedQuery.identifier(tokens[p]), KindWord.from(lower[p]) == nil, !ParsedQuery.stopWords.contains(lower[p]) {
                        constraints.append(.inFolder(name)); consumed[i] = true; consumed[p] = true
                    } else if let j = next(1), let name = ParsedQuery.identifier(tokens[j]), KindWord.from(lower[j]) == nil, !ParsedQuery.stopWords.contains(lower[j]) {
                        constraints.append(.inFolder(name)); consumed[i] = true; consumed[j] = true
                    }
                default:
                    break
                }
            }

            // Tags, kinds and free text.
            for i in tokens.indices where !consumed[i] {
                let t = lower[i]
                if t.hasPrefix("@") {
                    switch t {
                    case "@main": tags.insert("entry-point")
                    case "@state": tags.insert("@State")
                    case "@binding": tags.insert("@Binding")
                    case "@environment": tags.insert("@Environment")
                    case "@observable": tags.insert("@Observable")
                    case "@mainactor": tags.insert("@MainActor")
                    case "@test": kind = kind ?? .test
                    default: tags.insert(tokens[i])
                    }
                    continue
                }
                switch t {
                case "async", "asynchronous", "비동기", "await":
                    tags.insert("async")
                case "swiftui":
                    tags.insert("SwiftUI.View")
                case "observable":
                    tags.insert("@Observable")
                case "mainactor":
                    tags.insert("@MainActor")
                case "entry", "entrypoint", "진입점", "시작점", "메인":
                    tags.insert("entry-point")
                    if i + 1 < tokens.count, lower[i + 1] == "point" { consumed[i + 1] = true }
                case "point" where tags.contains("entry-point"):
                    break
                default:
                    if let k = KindWord.from(t) {
                        if k == .actor { tags.insert("actor") }
                        if kind == nil { kind = k } else { freeTokens.append(t) }
                    } else if !ParsedQuery.stopWords.contains(t) {
                        freeTokens.append(t)
                    }
                }
            }
        }

        /// Removes a trailing Korean particle ("View를" → "View", "뷰를" → "뷰").
        /// Latin stems are always stripped; Korean stems only when the remainder is a known kind or stop word,
        /// so ordinary Korean words ("쓰는", "안의") are left for the stop-word list to handle.
        static func stripParticles(_ token: String) -> String {
            for particle in koreanParticles where token.hasSuffix(particle) && token.count > particle.count {
                let stem = String(token.dropLast(particle.count))
                guard stem.contains(where: { $0.isLetter }) else { continue }
                if stem.unicodeScalars.contains(where: { $0.isASCII }) { return stem }
                let lower = stem.lowercased()
                if KindWord.from(lower) != nil || stopWords.contains(lower) { return stem }
            }
            return token
        }

        /// A token usable as a type / module / folder name (contains a Latin letter).
        static func identifier(_ token: String) -> String? {
            let t = token.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard t.unicodeScalars.contains(where: { $0.isASCII && CharacterSet.letters.contains($0) }) else { return nil }
            return t
        }
    }

    // MARK: - Scoring

    private func score(_ node: CodeNode, parsed: ParsedQuery, graph: CodeGraph) -> CodeSearchHit? {
        var total = 0.0
        var reasons: [String] = []

        // Kind filter.
        if let kind = parsed.kind {
            guard CodeSearcher.matches(kind: kind, node: node) else { return nil }
            total += 3
            reasons.append(kind.label)
        }

        // Tag filter.
        for tag in parsed.tags {
            guard CodeSearcher.hasTag(tag, node: node, graph: graph) else { return nil }
            total += 4
            reasons.append(tag == "entry-point" ? "entry point" : tag)
        }

        // Structural constraints.
        for c in parsed.constraints {
            guard CodeSearcher.satisfies(c, node: node, graph: graph) else { return nil }
            total += 5
            reasons.append(c.description)
        }

        // Free text.
        if !parsed.freeTokens.isEmpty {
            var textScore = 0.0
            for token in parsed.freeTokens {
                let (s, why) = CodeSearcher.textScore(token, node: node)
                if s > 0 {
                    textScore += s
                    reasons.append(why)
                }
            }
            if textScore == 0 {
                return nil
            }
            total += textScore
        } else if parsed.kind == nil && parsed.tags.isEmpty && parsed.constraints.isEmpty {
            return nil
        }

        // Light preference for spatial nodes when nothing else distinguishes.
        if node.kind.isSpatial { total += 0.1 }
        return CodeSearchHit(nodeID: node.id, score: total, reason: reasons.joined(separator: ", "))
    }

    static func matches(kind: KindWord, node: CodeNode) -> Bool {
        switch kind {
        case .view:
            return node.kind == .type && (node.tags.contains("SwiftUI.View") || node.name.hasSuffix("View") || node.name.hasSuffix("Screen"))
        case .model:
            guard node.kind == .type else { return false }
            if node.tags.contains("SwiftUI.View") { return false }
            return node.name.contains("Model") || node.path.contains("Model") || node.layer == .domain || node.tags.contains("@Observable")
        case .test:
            return (node.kind == .type || node.kind == .file || node.kind == .function || node.kind == .folder) && (node.tags.contains("test") || node.layer == .test)
        case .protocolType:
            return node.kind == .type && node.tags.contains("protocol")
        case .actor:
            return node.kind == .type && node.tags.contains("actor")
        case .extensionType:
            return node.kind == .extensionDecl
        case .enumType:
            return node.kind == .type && node.tags.contains("enum")
        case .structType:
            return node.kind == .type && node.tags.contains("struct")
        case .classType:
            return node.kind == .type && node.tags.contains("class")
        case .function:
            return node.kind == .function
        case .property:
            return node.kind == .property
        case .folder:
            return node.kind == .folder || node.kind == .module
        case .file:
            return node.kind == .file
        case .type:
            return node.kind == .type
        }
    }

    static func hasTag(_ tag: String, node: CodeNode, graph: CodeGraph) -> Bool {
        if node.tags.contains(tag) { return true }
        // Tags recorded on members (e.g. @State on a property) count for the declaring type and file.
        if node.kind == .type || node.kind == .file || node.kind == .extensionDecl {
            return graph.subtree(of: node.id).dropFirst().contains { $0.tags.contains(tag) }
        }
        return false
    }

    static func satisfies(_ c: Constraint, node: CodeNode, graph: CodeGraph) -> Bool {
        switch c {
        case .inherits(let name):
            let lower = name.lowercased()
            if node.kind == .type {
                if node.outgoing(graph, kind: .inherits).contains(where: { graph.node($0.to)?.name.lowercased() == lower }) { return true }
                if node.tags.contains(where: { $0.lowercased() == "inherits:\(lower)" }) { return true }
                if lower == "view" && node.tags.contains("SwiftUI.View") { return true }
                if lower == "app" && node.tags.contains("SwiftUI.App") { return true }
                return false
            }
            if node.kind == .file {
                return graph.children(of: node.id).contains { satisfies(c, node: $0, graph: graph) }
            }
            return false
        case .imports(let name):
            let lower = name.lowercased()
            guard let file = node.kind == .file ? node : graph.file(containing: node.id) else { return false }
            if file.outgoing(graph, kind: .imports).contains(where: { graph.node($0.to)?.name.lowercased() == lower }) { return true }
            return file.tags.contains { $0.lowercased() == "imports:\(lower)" }
        case .references(let name):
            // Only files and symbols "use" something; folders are never answers to "what uses X".
            let lower = name.lowercased()
            guard let file = node.kind == .file ? node : graph.file(containing: node.id) else { return false }
            let sources = [node.id, file.id]
            for src in sources {
                for e in graph.outgoing(from: src, kinds: [.references, .inherits, .calls]) {
                    if graph.node(e.to)?.name.lowercased() == lower { return true }
                }
            }
            return false
        case .inFolder(let name):
            let lower = name.lowercased()
            if node.kind == .folder && node.name.lowercased() == lower { return false }
            return graph.ancestors(of: node.id).contains { ($0.kind == .folder || $0.kind == .module) && $0.name.lowercased() == lower }
        case .related(let relation, let outgoing, let name):
            // Files, types and extensions answer relation queries; their members' edges count for them.
            guard node.kind == .file || node.kind == .type || node.kind == .extensionDecl else { return false }
            let lower = name.lowercased()
            func named(_ id: NodeID) -> Bool {
                guard let other = graph.node(id) else { return false }
                let n = other.name.lowercased()
                return n == lower || (n.hasSuffix(".swift") && n.dropLast(6) == lower)
            }
            let members = graph.subtree(of: node.id)
            let inside = Set(members.map(\.id))
            for member in members {
                let edges = outgoing ? graph.outgoing(from: member.id) : graph.incoming(to: member.id)
                for e in edges where e.semantic == relation {
                    let other = outgoing ? e.to : e.from
                    if !inside.contains(other) && named(other) { return true }
                }
            }
            return false
        }
    }

    /// Best text match of one token against a node's name and path.
    static func textScore(_ token: String, node: CodeNode) -> (Double, String) {
        let name = node.name.lowercased()
        let bare = name.hasSuffix(".swift") ? String(name.dropLast(6)) : name
        if name == token || bare == token { return (10, "name is \"\(node.name)\"") }
        if bare.hasPrefix(token) { return (6, "name starts with \"\(token)\"") }
        if bare.contains(token) { return (4, "name contains \"\(token)\"") }
        if token.count >= 2, initials(of: node.name) == token { return (5, "initials match \"\(token)\"") }
        if token.count >= 5, levenshtein(bare, token, limit: 2) <= 2 { return (3, "name is close to \"\(token)\"") }
        if node.path.lowercased().contains(token) { return (2, "path contains \"\(token)\"") }
        return (0, "")
    }

    /// Camel-case initials: `NotesListViewModel` → "nlvm", `APIError` → "ae" (an acronym counts as one word).
    static func initials(of name: String) -> String {
        let chars = Array(name.prefix { $0 != "." })
        var out = ""
        for i in chars.indices where chars[i].isUppercase {
            let previousLower = i > 0 && chars[i - 1].isLowercase
            let nextLower = i + 1 < chars.count && chars[i + 1].isLowercase
            if i == 0 || previousLower || nextLower { out.append(chars[i].lowercased()) }
        }
        return out
    }

    /// Levenshtein distance with early exit once `limit` is exceeded.
    static func levenshtein(_ a: String, _ b: String, limit: Int) -> Int {
        let s = Array(a.unicodeScalars), t = Array(b.unicodeScalars)
        if abs(s.count - t.count) > limit { return limit + 1 }
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        var cur = Array(repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > limit { return limit + 1 }
            swap(&prev, &cur)
        }
        return prev[t.count]
    }
}

private extension CodeNode {
    func outgoing(_ graph: CodeGraph, kind: EdgeKind) -> [CodeEdge] {
        graph.outgoing(from: id, kinds: [kind])
    }
}
