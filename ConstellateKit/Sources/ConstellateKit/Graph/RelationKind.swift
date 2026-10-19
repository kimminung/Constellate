import Foundation

/// The *meaning* of a relation edge, layered on top of the structural `EdgeKind`.
///
/// Ported from CoulsonPortfolioWeb `Public/js/space/relations.js` (`EDGE_TYPES`), so the 3-D code space on the
/// web and the Constellate constellation speak the same visual language. `EdgeKind` stays the coarse,
/// stable category (what the ingestor saw: a reference, an inheritance clause, an import); `RelationKind`
/// says what the reference *does* — a view embedding another view, a screen presenting another, a model
/// feeding a view, a factory creating a type — which is what a developer actually wants to read off a graph.
///
/// Direction convention: every edge still points from the dependent to the dependency (`from` uses `to`), so
/// dependency analysis (`GraphInsights`) works on all kinds alike. Kinds whose *data* flows the other way
/// (`binds`: the observed model feeds the observing view) set `flowIsReversed`, and only the renderer flips them.
public enum RelationKind: String, Codable, Sendable, CaseIterable, Hashable {
    /// Type → protocol / superclass it adopts (채택·상속).
    case conforms
    /// `extension Foo` → `Foo` declared elsewhere (확장).
    case extends
    /// Parent view → child view it embeds (뷰 포함).
    case composes
    /// Screen → destination it presents via sheet / NavigationLink / WindowGroup / present() (화면 전환).
    case presents
    /// View → observed source via @State / @Environment / @Bindable … (상태 흐름; data flows source → view).
    case binds
    /// Creator → type it instantiates (생성).
    case creates
    /// Implementation → delegate / data-source protocol (델리게이트).
    case delegates
    /// Poster → observer of the same Notification name (알림; a runtime, not compile-time, coupling).
    case notifies
    /// Plain type reference — the most common and least informative kind, so it is drawn quietest (타입 참조).
    case uses
    /// File → module / top-level folder it imports.
    case imports
    /// Function → function it calls (reserved for call-graph extractors; nothing emits it yet).
    case calls

    /// Default relation for a structural edge whose flavour was not classified (`nil` for `contains`).
    public static func fallback(for kind: EdgeKind) -> RelationKind? {
        switch kind {
        case .contains: nil
        case .imports: .imports
        case .references: .uses
        case .inherits: .conforms
        case .calls: .calls
        }
    }

    /// Visual + semantic metadata. Colours are fixed across themes (like the code palette) so the legend
    /// never changes meaning when the environment is re-tinted.
    public var style: RelationStyle {
        switch self {
        case .conforms:  RelationStyle(labelKo: "채택·상속", labelEn: "Conforms", hint: "타입 → 프로토콜/부모 클래스", color: RGBA(hex: 0xBB9AF7), symbol: "arrow.triangle.branch", flow: false, dashed: true, lane: -0.62, altitude: 0.85, priority: 70)
        case .extends:   RelationStyle(labelKo: "확장", labelEn: "Extends", hint: "extension → 원본 타입", color: RGBA(hex: 0x7DCFFF), symbol: "puzzlepiece.extension", flow: false, dashed: true, lane: 0.18, altitude: 0.7, priority: 60)
        case .composes:  RelationStyle(labelKo: "뷰 포함", labelEn: "Composes", hint: "부모 뷰 → 자식 뷰", color: RGBA(hex: 0x7AA2F7), symbol: "square.on.square", flow: false, dashed: false, lane: 0.44, altitude: 1.0, priority: 80)
        case .presents:  RelationStyle(labelKo: "화면 전환", labelEn: "Presents", hint: "sheet / NavigationLink / present → 목적지", color: RGBA(hex: 0xFF9E64), symbol: "rectangle.portrait.and.arrow.right", flow: true, dashed: false, lane: 1.22, altitude: 1.45, priority: 95)
        case .binds:     RelationStyle(labelKo: "상태 흐름", labelEn: "Binds", hint: "데이터 원본 → 관찰하는 뷰", color: RGBA(hex: 0x9ECE6A), symbol: "arrow.triangle.2.circlepath", flow: true, dashed: false, lane: 0.87, altitude: 1.15, priority: 90)
        case .creates:   RelationStyle(labelKo: "생성", labelEn: "Creates", hint: "생성하는 곳 → 생성되는 타입", color: RGBA(hex: 0xE0AF68), symbol: "plus.square.on.square", flow: true, dashed: false, lane: -0.96, altitude: 1.25, priority: 85)
        case .delegates: RelationStyle(labelKo: "델리게이트", labelEn: "Delegates", hint: "구현 → 프로토콜", color: RGBA(hex: 0xF7768E), symbol: "person.2.wave.2", flow: true, dashed: true, lane: -0.35, altitude: 1.05, priority: 75)
        case .notifies:  RelationStyle(labelKo: "알림", labelEn: "Notifies", hint: "post → observe", color: RGBA(hex: 0xFFD60A), symbol: "bell.and.waves.left.and.right", flow: true, dashed: false, lane: -1.31, altitude: 1.6, priority: 88)
        case .uses:      RelationStyle(labelKo: "타입 참조", labelEn: "Uses", hint: "사용 → 정의", color: RGBA(hex: 0x8B93A5), symbol: "arrow.right", flow: false, dashed: false, lane: 0, altitude: 0.55, priority: 10)
        case .imports:   RelationStyle(labelKo: "import", labelEn: "Imports", hint: "파일 → 모듈/최상위 폴더", color: RGBA(hex: 0x58D7E8), symbol: "shippingbox", flow: false, dashed: false, lane: 0, altitude: 0.38, priority: 20)
        case .calls:     RelationStyle(labelKo: "호출", labelEn: "Calls", hint: "함수 → 함수", color: RGBA(hex: 0xFFD166), symbol: "phone.arrow.right", flow: true, dashed: false, lane: -1.1, altitude: 1.3, priority: 65)
        }
    }

    /// True when `from` cannot compile without `to` (used for cycles / impact). Notifications are runtime-only and
    /// imports point at folders, so neither counts.
    public var isDependency: Bool {
        switch self {
        case .notifies, .imports: false
        default: true
        }
    }

    /// Data flows `to → from` (the observed source feeds the observer). Renderers flip arrows and particles.
    public var flowIsReversed: Bool { self == .binds }

    /// Legend order: most informative first (matches `style.priority`).
    public static let legendOrder: [RelationKind] = allCases.sorted { $0.style.priority > $1.style.priority }
}

/// How a `RelationKind` looks and behaves in the constellation.
public struct RelationStyle: Hashable, Sendable {
    public var labelKo: String
    public var labelEn: String
    /// One-line explanation of the direction (shown in legends / tooltips).
    public var hint: String
    public var color: RGBA
    /// SF Symbol for 2-D legends.
    public var symbol: String
    /// Animated particles travel along the edge (and an arrowhead is drawn) — the portfolio's `flow` flag.
    public var flow: Bool
    /// Drawn as a dashed curve — the portfolio's `dashed` flag (type-system relations, not runtime ones).
    public var dashed: Bool
    /// Rotation (radians) of the arc's bulge around the chord. Different kinds between the same two cards fan out
    /// into separate "lanes" instead of drawing on top of each other.
    public var lane: Float
    /// Multiplier for the arc's bulge height: informative kinds fly higher, plain references hug the chord.
    public var altitude: Float
    /// Higher = more informative; used for legend order and for picking a dominant kind.
    public var priority: Int

    /// "상태 흐름 · Binds"
    public var label: String { "\(labelKo) · \(labelEn)" }
}

public extension CodeEdge {
    /// The relation's meaning: the classified flavour, else the structural fallback (`nil` only for `contains`).
    var semantic: RelationKind? { relation ?? RelationKind.fallback(for: kind) }
}

// MARK: - Roles

/// What a file (or type) is *for*, inferred from its path, name and source. Ported from the portfolio's
/// `inferRole` and `ROLES`. Drives the star glyph shape, the card's role chip and the composes/creates split.
public enum CodeRole: String, Codable, Sendable, CaseIterable, Hashable {
    case app, view, controller, viewModel, model, service, extensionRole = "extension", test, doc, config, script, other

    public var style: RoleStyle {
        switch self {
        case .app:           RoleStyle(label: "App", color: RGBA(hex: 0xF7768E), symbol: "app.badge", glyph: "Star_App")
        case .view:          RoleStyle(label: "View", color: RGBA(hex: 0x7AA2F7), symbol: "rectangle.on.rectangle", glyph: "Star_View")
        case .controller:    RoleStyle(label: "Controller", color: RGBA(hex: 0x7DCFFF), symbol: "slider.horizontal.3", glyph: "Star_Controller")
        case .viewModel:     RoleStyle(label: "ViewModel", color: RGBA(hex: 0xBB9AF7), symbol: "point.3.connected.trianglepath.dotted", glyph: "Star_ViewModel")
        case .model:         RoleStyle(label: "Model", color: RGBA(hex: 0x9ECE6A), symbol: "cube", glyph: "Star_Model")
        case .service:       RoleStyle(label: "Service", color: RGBA(hex: 0xE0AF68), symbol: "gearshape.2", glyph: "Star_Service")
        case .extensionRole: RoleStyle(label: "Extension", color: RGBA(hex: 0x8B93A5), symbol: "puzzlepiece.extension", glyph: "Star_Extension")
        case .test:          RoleStyle(label: "Test", color: RGBA(hex: 0xFF9E64), symbol: "checkmark.seal", glyph: "Star_Test")
        case .doc:           RoleStyle(label: "Doc", color: RGBA(hex: 0x8B93A5), symbol: "doc.text", glyph: "Star_Doc")
        case .config:        RoleStyle(label: "Config", color: RGBA(hex: 0x8B93A5), symbol: "gearshape", glyph: "Star_Config")
        case .script:        RoleStyle(label: "Script", color: RGBA(hex: 0x89E051), symbol: "terminal", glyph: "Star_Script")
        case .other:         RoleStyle(label: "", color: RGBA(hex: 0x8B93A5), symbol: "circle.dotted", glyph: "Star_Other")
        }
    }
}

public struct RoleStyle: Hashable, Sendable {
    /// Chip text (empty for `.other`, which shows no chip — same as the portfolio).
    public var label: String
    public var color: RGBA
    public var symbol: String
    /// Name of the glyph prim inside `NodeStars.usdz` (Blender/scripts/build_graph_assets.py).
    public var glyph: String
}

public extension CodeNode {
    /// Glyph name for this node: role glyph for files / types, hub glyphs for folders and the module.
    var starGlyphName: String {
        switch kind {
        case .module: "Star_Module"
        case .folder: "Star_Folder"
        default: (role ?? .other).style.glyph
        }
    }
}
