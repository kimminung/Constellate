import Foundation

/// A symbol found in one source file.
public struct ExtractedSymbol: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case `struct`, `class`, `enum`, `actor`, `protocol`, `extension`, function, property }
    public var name: String
    public var kind: Kind
    public var lines: LineRange
    /// Declared supertypes / conformances (for `inherits` edges).
    public var inherits: [String]
    public var tags: Set<String>
    /// Name of the enclosing type, if nested.
    public var parentName: String?

    public init(name: String, kind: Kind, lines: LineRange, inherits: [String] = [], tags: Set<String> = [], parentName: String? = nil) {
        self.name = name
        self.kind = kind
        self.lines = lines
        self.inherits = inherits
        self.tags = tags
        self.parentName = parentName
    }

    public var nodeKind: NodeKind {
        switch kind {
        case .struct, .class, .enum, .actor, .protocol: .type
        case .extension: .extensionDecl
        case .function: .function
        case .property: .property
        }
    }
}

public struct ExtractedFile: Hashable, Codable, Sendable {
    public var imports: [String]
    public var symbols: [ExtractedSymbol]
    /// Capitalised identifiers used in the file (candidate `references` edges to types).
    public var referencedTypeNames: Set<String>
    public var lineCount: Int
    public var tags: Set<String>

    public init(imports: [String] = [], symbols: [ExtractedSymbol] = [], referencedTypeNames: Set<String> = [], lineCount: Int = 0, tags: Set<String> = []) {
        self.imports = imports
        self.symbols = symbols
        self.referencedTypeNames = referencedTypeNames
        self.lineCount = lineCount
        self.tags = tags
    }
}

/// Lightweight, dependency-free Swift symbol extractor (line + brace scanning; no SwiftSyntax).
/// Good enough for layout, search and AI grounding; not a compiler.
///
/// What it finds:
/// - `import X` statements,
/// - `struct` / `class` / `enum` / `actor` / `protocol` / `extension` declarations (with inheritance lists
///   and nesting), `func` declarations at type or top-level scope, and `var` / `let` at type or top-level scope,
/// - line ranges by matching braces from the declaration line,
/// - tags: `SwiftUI.View`, `SwiftUI.App`, `@Observable`, `@MainActor`, `actor`, `async`, `entry-point`, `test`,
///   `@State` / `@Binding` / `@Environment` (on the property, its enclosing type and the file) plus the
///   declaration kind itself (`struct`, `class`, `enum`, `actor`, `protocol`),
/// - `referencedTypeNames`: capitalised identifiers that are not declared in the file and not well-known
///   Swift / Foundation names.
///
/// Comments and string literal contents are stripped before matching.
public struct SwiftSymbolExtractor: Sendable {
    public init() {}

    public func extract(source: String) -> ExtractedFile {
        let cleaned = SwiftSymbolExtractor.stripCommentsAndStrings(source)
        let lineCount = SwiftSymbolExtractor.lineCount(of: source)

        var scanner = Scanner(lines: cleaned)
        scanner.run()

        var file = ExtractedFile(
            imports: scanner.imports,
            symbols: scanner.symbols,
            referencedTypeNames: [],
            lineCount: lineCount,
            tags: scanner.fileTags
        )

        // References: capitalised identifiers minus declared names, imports and well-known names.
        let declared = Set(scanner.symbols.map(\.name))
        let imported = Set(scanner.imports)
        var refs: Set<String> = []
        for line in cleaned {
            guard line.utf8.contains(where: { $0 >= 65 && $0 <= 90 }) else { continue }
            let ns = line as NSString
            for m in Patterns.capitalised.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let name = ns.substring(with: m.range)
                if declared.contains(name) || imported.contains(name) || Patterns.wellKnownNames.contains(name) { continue }
                refs.insert(name)
            }
        }
        file.referencedTypeNames = refs

        if imported.contains("Testing") || imported.contains("XCTest") {
            file.tags.insert("test")
        }
        return file
    }

    /// Number of lines in `source`: newline count, plus one when the last line has no trailing newline.
    public static func lineCount(of source: String) -> Int {
        var count = 0
        var last: UInt8 = 10
        for b in source.utf8 {
            if b == 10 { count += 1 }
            last = b
        }
        if last != 10 { count += 1 }
        return count
    }

    // MARK: - Cleaning

    /// Removes `//` and `/* */` comments and the contents of string literals (keeping interpolated code),
    /// preserving line structure. Returns one entry per line.
    static func stripCommentsAndStrings(_ source: String) -> [String] {
        let bytes = Array(source.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)

        enum State { case code, lineComment, blockComment(depth: Int), string(multiline: Bool, interpolation: Int) }
        var state = State.code
        var i = 0
        let n = bytes.count

        @inline(__always) func at(_ k: Int) -> UInt8 { k < n ? bytes[k] : 0 }

        while i < n {
            let c = bytes[i]
            switch state {
            case .code:
                if c == 47 && at(i + 1) == 47 { // //
                    state = .lineComment
                    i += 2
                } else if c == 47 && at(i + 1) == 42 { // /*
                    state = .blockComment(depth: 1)
                    i += 2
                } else if c == 34 { // "
                    if at(i + 1) == 34 && at(i + 2) == 34 {
                        state = .string(multiline: true, interpolation: 0)
                        out.append(34); out.append(34)
                        i += 3
                    } else {
                        state = .string(multiline: false, interpolation: 0)
                        out.append(34); out.append(34)
                        i += 1
                    }
                } else {
                    out.append(c)
                    i += 1
                }
            case .lineComment:
                if c == 10 {
                    out.append(10)
                    state = .code
                }
                i += 1
            case .blockComment(let depth):
                if c == 42 && at(i + 1) == 47 { // */
                    state = depth > 1 ? .blockComment(depth: depth - 1) : .code
                    i += 2
                } else if c == 47 && at(i + 1) == 42 { // nested /*
                    state = .blockComment(depth: depth + 1)
                    i += 2
                } else {
                    if c == 10 { out.append(10) }
                    i += 1
                }
            case .string(let multiline, let interpolation):
                if interpolation > 0 {
                    // Inside \( … ): emit code, track parentheses.
                    if c == 40 { state = .string(multiline: multiline, interpolation: interpolation + 1) }
                    else if c == 41 {
                        state = .string(multiline: multiline, interpolation: interpolation - 1)
                        if interpolation - 1 == 0 { i += 1; continue }
                    }
                    if c == 10 { out.append(10) } else if interpolation > 0 { out.append(c) }
                    i += 1
                    continue
                }
                if c == 92 { // backslash
                    if at(i + 1) == 40 { // \(
                        state = .string(multiline: multiline, interpolation: 1)
                        out.append(32)
                        i += 2
                    } else {
                        if at(i + 1) == 10 { out.append(10) }
                        i += 2
                    }
                } else if c == 34 {
                    if multiline {
                        if at(i + 1) == 34 && at(i + 2) == 34 {
                            state = .code
                            i += 3
                        } else {
                            i += 1
                        }
                    } else {
                        state = .code
                        i += 1
                    }
                } else if c == 10 {
                    out.append(10)
                    // Unterminated single-line string: recover at the newline.
                    if !multiline { state = .code }
                    i += 1
                } else {
                    i += 1
                }
            }
        }

        var lines: [String] = []
        var start = 0
        for (k, b) in out.enumerated() where b == 10 {
            lines.append(String(decoding: out[start..<k], as: UTF8.self))
            start = k + 1
        }
        // Final line (possibly empty) so indices match 1-based source lines.
        lines.append(String(decoding: out[start..<out.count], as: UTF8.self))
        return lines
    }

    // MARK: - Patterns (compiled once)

    enum Patterns {
        static let typeDecl = regex(#"(?:^|[\s;{}])(struct|class|enum|actor|protocol|extension)\s+([A-Za-z_][A-Za-z0-9_.]*)"#)
        static let funcDecl = regex(#"(?:^|[\s;{}])func\s+([^\s(<]+)"#)
        static let propertyDecl = regex(#"(?:^|[\s;{}])(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)"#)
        static let importDecl = regex(#"^\s*(?:@[A-Za-z_]+(?:\([^)]*\))?\s+)*import\s+(?:(?:struct|class|enum|protocol|func|var|let|typealias)\s+)?([A-Za-z_][A-Za-z0-9_]*)"#)
        static let attribute = regex(#"@[A-Za-z_][A-Za-z0-9_]*"#)
        static let capitalised = regex(#"\b[A-Z][A-Za-z0-9_]{2,}\b"#)
        static let asyncKeyword = regex(#"\basync\b"#)

        static let swiftKeywords: Set<String> = [
            "func", "var", "let", "class", "struct", "enum", "actor", "protocol", "extension", "import", "init", "deinit",
            "subscript", "typealias", "associatedtype", "case", "default", "where", "static", "final", "override",
            "private", "fileprivate", "internal", "public", "open", "mutating", "nonmutating", "lazy", "weak", "unowned",
            "some", "any", "inout", "throws", "rethrows", "async", "await", "try", "return", "if", "else", "guard",
            "switch", "for", "while", "repeat", "break", "continue", "in", "is", "as", "nil", "true", "false", "self",
            "super", "convenience", "required", "indirect", "operator", "precedencegroup", "defer", "do", "catch",
            "throw", "fallthrough", "get", "set", "willSet", "didSet", "consuming", "borrowing", "macro"
        ]

        static let wellKnownNames: Set<String> = [
            "String", "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Bool", "Double", "Float", "Float16", "Float32", "Float64", "Float80", "CGFloat", "Character", "Substring",
            "Array", "Dictionary", "Set", "Optional", "Range", "ClosedRange", "Slice", "ArraySlice", "ContiguousArray",
            "Error", "Date", "URL", "UUID", "Data", "Task", "TaskGroup", "ThrowingTaskGroup", "Self", "Any", "AnyObject",
            "Void", "Never", "Result", "Codable", "Encodable", "Decodable", "Hashable", "Equatable", "Identifiable",
            "Sendable", "Comparable", "CaseIterable", "RawRepresentable", "Collection", "Sequence", "Iterator",
            "IteratorProtocol", "BidirectionalCollection", "RandomAccessCollection", "MutableCollection",
            "RangeReplaceableCollection", "Element", "Index", "Key", "Value", "SIMD2", "SIMD3", "SIMD4", "SIMD8",
            "SIMD16", "Hasher", "Mirror", "ObjectIdentifier", "AnyHashable", "KeyPath", "WritableKeyPath",
            "ReferenceWritableKeyPath", "PartialKeyPath", "AnyKeyPath", "Unmanaged", "UnsafePointer",
            "UnsafeMutablePointer", "UnsafeRawPointer", "UnsafeMutableRawPointer", "UnsafeBufferPointer",
            "UnsafeMutableBufferPointer", "OpaquePointer", "Character", "Unicode", "StaticString", "Decoder",
            "Encoder", "JSONDecoder", "JSONEncoder", "PropertyListDecoder", "PropertyListEncoder", "CodingKey",
            "CodingKeys", "KeyedDecodingContainer", "KeyedEncodingContainer", "DateFormatter", "NumberFormatter",
            "Calendar", "Locale", "TimeZone", "TimeInterval", "DateComponents", "Measurement", "FileManager",
            "Bundle", "Notification", "NotificationCenter", "NSObject", "NSString", "NSRange", "NSRegularExpression",
            "NSError", "NSNumber", "NSPredicate", "NSSortDescriptor", "Foundation", "Swift", "Dispatch", "DispatchQueue",
            "DispatchGroup", "DispatchTime", "MainActor", "GlobalActor", "Actor", "AnyActor", "Observable",
            "ObservableObject", "Published", "State", "Binding", "Environment", "EnvironmentObject", "StateObject",
            "ObservedObject", "FocusState", "AppStorage", "SceneStorage", "Query", "Bindable", "Namespace",
            "GestureState", "ViewBuilder", "SceneBuilder", "ToolbarContentBuilder", "CommandsBuilder", "Text", "Image",
            "Button", "Toggle", "Slider", "Stepper", "Picker", "List", "Form", "Section", "ForEach", "VStack", "HStack",
            "ZStack", "LazyVStack", "LazyHStack", "LazyVGrid", "LazyHGrid", "Grid", "GridRow", "ScrollView",
            "NavigationStack", "NavigationSplitView", "NavigationLink", "TabView", "Spacer", "Divider", "Group",
            "GroupBox", "Label", "TextField", "SecureField", "TextEditor", "Menu", "Color", "Font", "Shape", "Circle",
            "Rectangle", "RoundedRectangle", "Capsule", "Ellipse", "Path", "Canvas", "GeometryReader",
            "GeometryProxy", "Animation", "Transaction", "EdgeInsets", "Alignment", "Axis", "Edge", "Angle",
            "UnitPoint", "CGPoint", "CGSize", "CGRect", "CGVector", "CGAffineTransform", "Scene", "WindowGroup",
            "Settings", "Commands", "CommandMenu", "CommandGroup", "View", "App", "Widget", "ViewModifier",
            "AnyView", "EmptyView", "TupleView", "ModifiedContent", "PreviewProvider", "Preview", "DocumentGroup",
            "ImmersiveSpace", "RealityView", "Entity", "ModelEntity", "AnchorEntity", "Transform", "SwiftUI",
            "Combine", "AnyCancellable", "PassthroughSubject", "CurrentValueSubject", "Publisher", "Just",
            "Testing", "XCTest", "XCTestCase", "Test", "Suite", "Expectation", "Issue", "LocalizedError",
            "CustomStringConvertible", "CustomDebugStringConvertible", "ExpressibleByStringLiteral",
            "ExpressibleByIntegerLiteral", "ExpressibleByArrayLiteral", "ExpressibleByDictionaryLiteral",
            "ExpressibleByNilLiteral", "ExpressibleByFloatLiteral", "ExpressibleByBooleanLiteral", "Strideable",
            "Numeric", "SignedNumeric", "BinaryInteger", "FixedWidthInteger", "FloatingPoint", "BinaryFloatingPoint",
            "SignedInteger", "UnsignedInteger", "AdditiveArithmetic", "Duration", "ContinuousClock", "Clock",
            "AsyncStream", "AsyncThrowingStream", "AsyncSequence", "AsyncIteratorProtocol", "CheckedContinuation",
            "UnsafeContinuation", "CancellationError", "Sorted", "Mutex", "Atomic", "Synchronization", "Logger",
            "OSLog", "URLSession", "URLRequest", "URLResponse", "HTTPURLResponse", "URLComponents", "URLQueryItem",
            "ProcessInfo", "OperationQueue", "Operation", "Thread", "RunLoop", "Timer", "Stream", "InputStream",
            "OutputStream", "FileHandle", "Pipe", "Process", "UserDefaults", "NSCoder", "NSCoding", "IndexSet",
            "IndexPath", "Decimal", "CharacterSet", "Scanner", "AttributedString", "NSAttributedString",
            "LocalizedStringKey", "LocalizedStringResource", "Predicate", "SortDescriptor", "KeyPathComparator",
            "ComparisonResult", "SortOrder", "Model", "Attribute", "Relationship", "ModelContext", "ModelContainer",
            "Schema", "FetchDescriptor", "PersistentModel", "SwiftData", "Int128", "UInt128", "MemoryLayout", "Zip2Sequence",
            "EnumeratedSequence", "LazySequence", "ReversedCollection", "Repeated", "StrideTo", "StrideThrough",
            "DefaultIndices", "AnySequence", "AnyIterator", "AnyCollection", "OptionSet", "TextOutputStream",
            "LosslessStringConvertible", "CVarArg", "Regex", "RegexComponent", "RegexBuilder", "AnyRegexOutput"
        ]

        private static func regex(_ pattern: String) -> NSRegularExpression {
            // Patterns are literals checked by the test-suite; a malformed one is a programmer error.
            guard let r = try? NSRegularExpression(pattern: pattern) else {
                preconditionFailure("invalid regex \(pattern)")
            }
            return r
        }
    }

    // MARK: - Scanner

    /// Walks cleaned lines, tracking brace scope so declarations get line ranges and parents.
    private struct Scanner {
        let lines: [String]
        var imports: [String] = []
        var symbols: [ExtractedSymbol] = []
        var fileTags: Set<String> = []

        /// One open `{`. `symbol` is the index in `symbols` whose body this brace opens (if any).
        private struct Scope {
            var symbol: Int?
            var isType: Bool
            var isProtocol: Bool
        }
        private var scopes: [Scope] = []
        /// Symbol waiting for its opening brace (multi-line signatures).
        private var pendingBody: Int?
        /// Attributes seen on preceding lines that have not yet been attached to a declaration.
        private var pendingAttributes: Set<String> = []

        init(lines: [String]) {
            self.lines = lines
        }

        mutating func run() {
            for (idx, line) in lines.enumerated() {
                let lineNumber = idx + 1
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }

                // Attributes (possibly on their own line).
                var attrs = pendingAttributes
                if line.utf8.contains(64) { // '@'
                    for a in attributes(in: line) { attrs.insert(a) }
                }

                let declared = detectDeclaration(line: line, lineNumber: lineNumber, attributes: attrs)
                if declared {
                    pendingAttributes = []
                } else if trimmed.hasPrefix("@") {
                    pendingAttributes = attrs
                } else if !trimmed.hasPrefix("{") {
                    pendingAttributes = []
                }

                scanBraces(line: line, lineNumber: lineNumber)
            }
            // Unterminated scopes end at the last line.
            let last = max(1, lines.count)
            while let scope = scopes.popLast() {
                if let s = scope.symbol {
                    symbols[s].lines.end = max(symbols[s].lines.start, last)
                }
            }
            pendingBody = nil
            finaliseTags()
        }

        // MARK: Declarations

        /// Index of the type whose body we are directly inside (nil at top level or inside a function / closure).
        private var currentTypeIndex: Int? {
            guard let top = scopes.last, top.isType else { return nil }
            return top.symbol
        }

        /// True when declarations on this line should be recorded: top level, or directly inside a type body.
        /// Anonymous braces (init/deinit/subscript bodies, closures, `do` blocks) hide their contents.
        private var isDeclarationScope: Bool {
            guard let top = scopes.last else { return true }
            return top.symbol != nil && top.isType
        }

        private var insideProtocol: Bool {
            scopes.last?.isProtocol ?? false
        }

        private mutating func detectDeclaration(line: String, lineNumber: Int, attributes: Set<String>) -> Bool {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)

            if line.contains("import"), let m = Patterns.importDecl.firstMatch(in: line, range: range) {
                let module = ns.substring(with: m.range(at: 1))
                if !imports.contains(module) { imports.append(module) }
                return true
            }

            guard isDeclarationScope else { return false }
            let parentName = currentTypeIndex.map { symbols[$0].name }

            if let m = Patterns.typeDecl.firstMatch(in: line, range: range) {
                let keyword = ns.substring(with: m.range(at: 1))
                let name = ns.substring(with: m.range(at: 2))
                if !Patterns.swiftKeywords.contains(name), let kind = ExtractedSymbol.Kind(rawValue: keyword) {
                    let inherits = parseInheritance(ns, from: m.range.location + m.range.length)
                    var tags: Set<String> = [keyword]
                    if inherits.contains("View") { tags.insert("SwiftUI.View") }
                    if inherits.contains("App") { tags.insert("SwiftUI.App") }
                    if attributes.contains("@Observable") { tags.insert("@Observable") }
                    if attributes.contains("@MainActor") { tags.insert("@MainActor") }
                    if attributes.contains("@main") { tags.insert("entry-point"); fileTags.insert("entry-point") }
                    if kind == .actor { tags.insert("actor") }
                    if name.hasSuffix("Tests") || inherits.contains("XCTestCase") { tags.insert("test") }
                    let symbol = ExtractedSymbol(name: name, kind: kind, lines: LineRange(start: lineNumber, end: lineNumber), inherits: inherits, tags: tags, parentName: parentName)
                    symbols.append(symbol)
                    pendingBody = symbols.count - 1
                    return true
                }
            }

            if line.contains("func"), let m = Patterns.funcDecl.firstMatch(in: line, range: range) {
                let name = ns.substring(with: m.range(at: 1))
                var tags: Set<String> = []
                let signature = ns.substring(from: m.range.location)
                let sigRange = NSRange(location: 0, length: (signature as NSString).length)
                if Patterns.asyncKeyword.firstMatch(in: signature, range: sigRange) != nil { tags.insert("async") }
                if attributes.contains("@MainActor") { tags.insert("@MainActor") }
                if attributes.contains("@Test") { tags.insert("test") }
                let symbol = ExtractedSymbol(name: name, kind: .function, lines: LineRange(start: lineNumber, end: lineNumber), tags: tags, parentName: parentName)
                symbols.append(symbol)
                // Protocol requirements have no body; otherwise wait for `{`.
                pendingBody = insideProtocol ? nil : symbols.count - 1
                return true
            }

            if (line.contains("var") || line.contains("let")), let m = Patterns.propertyDecl.firstMatch(in: line, range: range) {
                let name = ns.substring(with: m.range(at: 1))
                var tags: Set<String> = []
                for wrapper in ["@State", "@Binding", "@Environment", "@StateObject", "@ObservedObject", "@EnvironmentObject", "@Published", "@Query", "@AppStorage", "@Bindable", "@FocusState"] where attributes.contains(wrapper) {
                    tags.insert(wrapper)
                    if ["@State", "@Binding", "@Environment"].contains(wrapper) {
                        fileTags.insert(wrapper)
                        if let t = currentTypeIndex { symbols[t].tags.insert(wrapper) }
                    }
                }
                let symbol = ExtractedSymbol(name: name, kind: .property, lines: LineRange(start: lineNumber, end: lineNumber), tags: tags, parentName: parentName)
                symbols.append(symbol)
                // Computed property: bind to a brace only when it opens on the same line.
                let rest = ns.substring(from: m.range.location + m.range.length)
                pendingBody = (!insideProtocol && rest.contains("{")) ? symbols.count - 1 : nil
                return true
            }

            return false
        }

        /// Parses `: A, B<C>, D where …` following a type name. Returns conformances with generic arguments removed.
        private func parseInheritance(_ ns: NSString, from location: Int) -> [String] {
            var i = location
            let n = ns.length
            // skip generic parameter list
            while i < n, ns.character(at: i) == 32 { i += 1 }
            if i < n, ns.character(at: i) == 60 { // <
                var depth = 0
                while i < n {
                    let c = ns.character(at: i)
                    if c == 60 { depth += 1 }
                    if c == 62 { depth -= 1; if depth == 0 { i += 1; break } }
                    i += 1
                }
            }
            while i < n, ns.character(at: i) == 32 { i += 1 }
            guard i < n, ns.character(at: i) == 58 else { return [] } // ':'
            i += 1
            var list = ns.substring(from: i)
            if let brace = list.firstIndex(of: "{") { list = String(list[..<brace]) }
            if let whereRange = list.range(of: " where ") { list = String(list[..<whereRange.lowerBound]) }
            if list.hasSuffix(" where") { list.removeLast(6) }
            var names: [String] = []
            var depth = 0
            var current = ""
            for ch in list {
                if ch == "<" { depth += 1; continue }
                if ch == ">" { depth -= 1; continue }
                if depth > 0 { continue }
                if ch == "," {
                    let t = current.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { names.append(t) }
                    current = ""
                } else {
                    current.append(ch)
                }
            }
            let t = current.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { names.append(t) }
            // Strip attributes like `@unchecked Sendable`, module prefixes `SwiftUI.View`, and `some`.
            let cleaned = names.compactMap { raw -> String? in
                var s = raw
                if s.hasPrefix("@") {
                    s = s.split(separator: " ", maxSplits: 1).dropFirst().joined(separator: " ")
                }
                s = s.replacingOccurrences(of: "any ", with: "").replacingOccurrences(of: "some ", with: "")
                if let dot = s.lastIndex(of: ".") { s = String(s[s.index(after: dot)...]) }
                s = s.trimmingCharacters(in: .whitespaces)
                guard let first = s.first, first.isLetter || first == "_" else { return nil }
                return s
            }
            return cleaned
        }

        private func attributes(in line: String) -> [String] {
            let ns = line as NSString
            return Patterns.attribute.matches(in: line, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        }

        // MARK: Braces

        private mutating func scanBraces(line: String, lineNumber: Int) {
            for b in line.utf8 {
                if b == 123 { // {
                    if let s = pendingBody {
                        let kind = symbols[s].kind
                        let isType = kind != .function && kind != .property
                        scopes.append(Scope(symbol: s, isType: isType, isProtocol: kind == .protocol))
                        pendingBody = nil
                    } else {
                        scopes.append(Scope(symbol: nil, isType: false, isProtocol: false))
                    }
                } else if b == 125 { // }
                    if let scope = scopes.popLast(), let s = scope.symbol {
                        symbols[s].lines.end = max(symbols[s].lines.start, lineNumber)
                    }
                    // A closing brace before the pending body appeared means the declaration had no body.
                    if pendingBody != nil { pendingBody = nil }
                }
            }
        }

        // MARK: Tags

        private mutating func finaliseTags() {
            // Propagate member tags upward: a type containing an async func is itself tagged async;
            // nested types inherit nothing else.
            var byName: [String: [Int]] = [:]
            for (i, s) in symbols.enumerated() where s.kind != .function && s.kind != .property {
                byName[s.name, default: []].append(i)
            }
            for s in symbols where s.kind == .function && s.tags.contains("async") {
                if let parent = s.parentName, let idxs = byName[parent] {
                    for i in idxs { symbols[i].tags.insert("async") }
                }
                fileTags.insert("async")
            }
            if symbols.contains(where: { $0.tags.contains("SwiftUI.View") }) { fileTags.insert("SwiftUI.View") }
            if symbols.contains(where: { $0.tags.contains("@Observable") }) { fileTags.insert("@Observable") }
            if symbols.contains(where: { $0.tags.contains("@MainActor") }) { fileTags.insert("@MainActor") }
            if symbols.contains(where: { $0.kind == .actor }) { fileTags.insert("actor") }
            if symbols.contains(where: { $0.tags.contains("test") }) { fileTags.insert("test") }
        }
    }
}
