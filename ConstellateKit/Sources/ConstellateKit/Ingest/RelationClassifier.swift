import Foundation

/// What one file does with a type name it mentions, strongest evidence first
/// (`binds` > `presents` > `constructs` > `mentions`). Resolved into a `RelationKind` once the target's role is known.
public enum ReferenceFact: String, Codable, Sendable, Comparable {
    /// Only mentioned (type annotation, generic argument, static member …) → `uses`.
    case mentions
    /// `Name(` appears outside a presentation context → `composes` (view → view) or `creates`.
    case constructs
    /// `Name(` appears right after NavigationLink / .sheet / WindowGroup / present … → `presents`.
    case presents
    /// The name sits on a property-wrapper line (`@State`, `@Environment(Name.self)` …) → `binds`.
    case binds

    private var rank: Int {
        switch self {
        case .mentions: 0
        case .constructs: 1
        case .presents: 2
        case .binds: 3
        }
    }

    public static func < (lhs: ReferenceFact, rhs: ReferenceFact) -> Bool { lhs.rank < rhs.rank }
}

/// Swift port of CoulsonPortfolioWeb `Public/js/space/relations.js` (`inferRole`, `buildRelations`).
///
/// The web version runs one regular expression per (file, type name) pair. That is fine for a 50-file repo in a
/// browser but not for the 4000-file budget here (NFR-1.1), so this port makes two linear passes per file instead:
/// property-wrapper lines → bound names, and one `Name(` scan → constructor sites (each classified by the four lines
/// before it, exactly like the original). Comments and string contents are already stripped by
/// `SwiftSymbolExtractor`, which removes the original's false positives inside comments.
public enum RelationClassifier {

    // MARK: Roles

    /// Infers what a file is for. Rules and order follow the portfolio's `inferRole`; `path` should include the
    /// module prefix (Constellate node paths do), which also fixes the original's miss on top-level `Models/` folders.
    /// - Parameters:
    ///   - symbols: extracted symbols when available (used for the "only extensions" rule).
    public static func inferRole(path: String, language: String?, source: String?, symbols: [ExtractedSymbol]? = nil) -> CodeRole {
        let name = (path as NSString).lastPathComponent
        let lang = language ?? ""
        if lang == "markdown" { return .doc }
        if ["json", "yaml", "ini", "xml", "plist"].contains(lang) || Patterns.configName.matches(name) { return .config }
        if ["shell", "bash", "makefile", "dockerfile"].contains(lang) { return .script }
        guard lang == "swift" else {
            return Patterns.testFolder.matches(path) ? .test : .other
        }
        guard let text = source, !text.isEmpty else { return .other }
        if Patterns.mainAttribute.matches(text) || Patterns.appConformance.matches(text) { return .app }
        if Patterns.testName.matches(name) || Patterns.testImport.matches(text) { return .test }
        if Patterns.controllerName.matches(name) || Patterns.uiControllerConformance.matches(text) { return .controller }
        if Patterns.viewModelName.matches(name) { return .viewModel }
        if Patterns.viewBody.matches(text) { return .view }
        if Patterns.serviceName.matches(name) { return .service }
        if let symbols {
            let decls = symbols.filter { $0.kind != .function && $0.kind != .property }
            if !decls.isEmpty && decls.allSatisfy({ $0.kind == .extension }) { return .extensionRole }
        }
        if Patterns.modelFolder.matches(path) || Patterns.modelConformance.matches(text) { return .model }
        if Patterns.viewFolder.matches(path) { return .view }
        if Patterns.serviceFolder.matches(path) { return .service }
        return .other
    }

    /// Role of a type node: its file's role, overridden by what the declaration itself says.
    public static func role(forType tags: Set<String>, kind: ExtractedSymbol.Kind, fileRole: CodeRole) -> CodeRole {
        if kind == .extension { return .extensionRole }
        if tags.contains("entry-point") || tags.contains("SwiftUI.App") { return .app }
        if tags.contains("test") { return .test }
        if tags.contains("SwiftUI.View") { return .view }
        return fileRole
    }

    // MARK: Reference facts

    /// Property wrappers whose argument / declared type is a data source the view observes.
    static let bindingWrappers = ["@Environment", "@EnvironmentObject", "@ObservedObject", "@StateObject", "@Bindable", "@State", "@Query", "@Observable"]

    /// Classifies how `cleanedLines` (comment/string-stripped source, one entry per line) uses each candidate name.
    /// Names that never appear get no entry; callers treat a missing entry as `.mentions`.
    public static func referenceFacts(cleanedLines: [String], candidates: Set<String>) -> [String: ReferenceFact] {
        guard !candidates.isEmpty else { return [:] }
        var facts: [String: ReferenceFact] = [:]
        func raise(_ name: String, _ fact: ReferenceFact) {
            guard candidates.contains(name) else { return }
            if let old = facts[name], old >= fact { return }
            facts[name] = fact
        }

        // Pass 1 — bindings: any capitalised identifier after a binding wrapper on the same line,
        // plus `@Environment(Name.self)`. (The original: `@(Environment|…)\b[^\n]*\bName\b`.)
        for line in cleanedLines where line.utf8.contains(64) { // '@'
            guard let wrapperEnd = bindingWrapperEnd(in: line) else { continue }
            let tail = String(line[wrapperEnd...])
            for name in Patterns.capitalisedIdentifiers(in: tail) { raise(name, .binds) }
        }

        // Pass 2 — constructor sites: `Name(` → presents (when the 4 preceding lines show a presentation API)
        // or constructs. The window mirrors the original's `text.slice(index - 220, index)` → last 4 lines.
        let text = cleanedLines.joined(separator: "\n")
        let ns = text as NSString
        for match in Patterns.constructorCall.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1))
            guard candidates.contains(name), (facts[name] ?? .mentions) < .presents else { continue }
            let start = max(0, match.range.location - 220)
            let before = ns.substring(with: NSRange(location: start, length: match.range.location - start))
            let window = before.split(separator: "\n", omittingEmptySubsequences: false).suffix(4).joined(separator: "\n")
            raise(name, Patterns.presentationContext.matches(window) ? .presents : .constructs)
        }
        return facts
    }

    /// Index just past the first binding wrapper on the line (`@State`, `@Environment(` …), if any.
    private static func bindingWrapperEnd(in line: String) -> String.Index? {
        var best: String.Index?
        for wrapper in bindingWrappers {
            var searchStart = line.startIndex
            while let r = line.range(of: wrapper, range: searchStart..<line.endIndex) {
                // Word boundary: `@State` must not match `@StateObject` (that one is listed on its own anyway).
                let next = r.upperBound < line.endIndex ? line[r.upperBound] : " "
                if !(next.isLetter || next.isNumber || next == "_") {
                    if best == nil || r.upperBound < best! { best = r.upperBound }
                    break
                }
                searchStart = r.upperBound
            }
        }
        return best
    }

    // MARK: Notifications

    /// Notification names posted / observed in raw source (strings matter here: `Notification.Name("x")`).
    public static func notifications(in source: String) -> (posted: [String], observed: [String]) {
        guard source.contains("otification") || source.contains("post(") else { return ([], []) }
        let posted = Patterns.notificationPost.captures(in: source)
        let observed = Patterns.notificationObserve.captures(in: source)
        return (Array(Set(posted)).sorted(), Array(Set(observed)).sorted())
    }

    // MARK: Resolution

    /// Turns a fact into a relation once both roles are known (the original's composes-vs-creates rule).
    public static func relation(for fact: ReferenceFact, sourceRole: CodeRole?, targetRole: CodeRole?) -> RelationKind {
        switch fact {
        case .binds: return .binds
        case .presents: return .presents
        case .mentions: return .uses
        case .constructs:
            let composer: Set<CodeRole> = [.view, .app, .controller]
            if targetRole == .view, let sourceRole, composer.contains(sourceRole) { return .composes }
            return .creates
        }
    }

    /// `Delegate` / `DataSource` supertypes are delegation, everything else is conformance / inheritance.
    public static func inheritanceRelation(superName: String) -> RelationKind {
        superName.hasSuffix("Delegate") || superName.hasSuffix("DataSource") ? .delegates : .conforms
    }

    // MARK: Patterns

    enum Patterns {
        static let configName = Regex(#"\.(plist|xcconfig|entitlements|storyboard|xib)$"#, caseInsensitive: true)
        static let testFolder = Regex(#"/(test|tests|__tests__)/"#, caseInsensitive: true)
        static let mainAttribute = Regex(#"@main\b"#)
        static let appConformance = Regex(#":\s*App\s*\{"#)
        static let testName = Regex(#"Tests?\.swift$"#)
        static let testImport = Regex(#"import (XCTest|Testing)\b"#)
        static let controllerName = Regex(#"ViewController\b"#)
        static let uiControllerConformance = Regex(#":\s*UI\w*ViewController\b"#)
        static let viewModelName = Regex(#"ViewModel|Presenter|Coordinator\b"#)
        static let viewBody = Regex(#"\bvar\s+body\s*:\s*some\s+View\b|:\s*(some\s+)?View\s*\{|UIView\b|UITableViewCell\b|UICollectionViewCell\b|:\s*Scene\b"#)
        static let serviceName = Regex(#"(Service|Manager|Store|Client|Engine|Repository|Provider|Loader|Parser|Formatter|Analyzer|Summarizer|Extractor|Controller|Renderer|Builder|Factory|System|Tracker)\.swift$"#)
        static let modelFolder = Regex(#"/(Models?|Entities|Domain)/"#)
        static let modelConformance = Regex(#"(Codable|Identifiable|Hashable|Equatable)\b"#)
        static let viewFolder = Regex(#"/(Views?|Components|Screens|UI)/"#)
        static let serviceFolder = Regex(#"/(Services?|Network|Networking|Utils?|Utilities|Helpers|Rendering|Language|Layout)/"#)
        static let presentationContext = Regex(#"(NavigationLink|\.sheet\(|\.fullScreenCover\(|\.navigationDestination\(|\.popover\(|\.inspector\(|present\(|pushViewController\(|performSegue|show\(|setViewControllers|rootViewController\s*=|WindowGroup|ImmersiveSpace|Tab\()"#)
        static let constructorCall = Regex(#"\b([A-Z][A-Za-z0-9_]{2,})\s*\("#).raw
        static let capitalised = Regex(#"\b[A-Z][A-Za-z0-9_]{2,}\b"#).raw
        static let notificationPost = Regex(#"post\(\s*name:\s*(?:\.|Notification\.Name\(\s*")([A-Za-z_][\w]*)"#)
        static let notificationObserve = Regex(#"(?:addObserver\([^)]*forName:|publisher\(\s*for:|onReceive\(\s*NotificationCenter[^)]*\.publisher\(\s*for:)\s*(?:\.|Notification\.Name\(\s*")([A-Za-z_][\w]*)"#)

        static func capitalisedIdentifiers(in text: String) -> [String] {
            let ns = text as NSString
            return capitalised.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        }
    }

    /// Small NSRegularExpression wrapper (patterns are literals verified by `RelationTests`).
    struct Regex: @unchecked Sendable {
        let raw: NSRegularExpression

        init(_ pattern: String, caseInsensitive: Bool = false) {
            guard let r = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else {
                preconditionFailure("invalid regex \(pattern)")
            }
            raw = r
        }

        func matches(_ text: String) -> Bool {
            raw.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
        }

        /// First capture group of every match.
        func captures(in text: String) -> [String] {
            let ns = text as NSString
            return raw.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
                m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : nil
            }
        }
    }
}
