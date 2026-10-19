import Foundation

/// Layout strategies — the Swift counterpart of CoulsonPortfolioWeb's `Public/js/space/layouts/index.js` registry.
///
/// Contract (same as the web registry, expressed in Constellate's terms): a strategy turns a `CodeGraph` into a
/// `ConstellationLayout` whose placements cover every node; spatial nodes get a position, a card radius (from line
/// count) and `w` (recency), members inherit their nearest spatial ancestor. Strategies differ only in *where*
/// things go, so colour, size, glyph and time encode the same facts everywhere.
///
/// Adding a style: add a case, give it a label/summary below, implement a worker next to the others in this
/// folder (`SphereLayout`, `WallLayout` … are 100-line examples built on `LayoutContext`), dispatch it in
/// `ConstellationLayoutEngine.layout(_:)`, and add a test to `LayoutStyleTests` (every node placed, cards don't
/// overlap, floor clearance, determinism).
public enum LayoutStyle: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    /// 천구 — spherical shells: tree depth → distance, subtree → azimuth sector, architecture layer → elevation,
    /// recency → radial push. A 3-D amphitheatre of code around the viewer. The app's default.
    case celestial
    /// 셸 — the original hierarchical radial shells: a disc, architecture layer → height band.
    case shells
    /// 구 — portfolio `sphere.js`: every file/type on a Fibonacci sphere (dome) in path order, folders as hubs outside.
    case sphere
    /// 트리 방사형 — portfolio `treeRadial.js`: leaf-weighted sectors, depth rings that grow to fit their leaves.
    case treeRadial
    /// 벽 — portfolio `grid.js`, curved into a cylindrical wall facing the viewer (comfortable at any width).
    case wall
    /// 나선 — portfolio `spiral.js`: a rising helix in path order.
    case spiral

    public var id: String { rawValue }

    /// The style the app starts with. The engine's own default stays `.shells` for API compatibility.
    public static let appDefault: LayoutStyle = .celestial

    /// "천구 · Celestial"
    public var label: String {
        switch self {
        case .celestial: "천구 · Celestial"
        case .shells: "셸 · Shells"
        case .sphere: "구 · Sphere"
        case .treeRadial: "트리 방사형 · Tree radial"
        case .wall: "벽 · Wall"
        case .spiral: "나선 · Spiral"
        }
    }

    /// SF Symbol for pickers.
    public var symbol: String {
        switch self {
        case .celestial: "globe.americas"
        case .shells: "circle.circle"
        case .sphere: "circle.grid.3x3.circle"
        case .treeRadial: "point.3.filled.connected.trianglepath.dotted"
        case .wall: "rectangle.split.3x3"
        case .spiral: "tornado"
        }
    }

    /// What each spatial axis means in this style (shown under the picker so the space stays readable).
    public var axes: String {
        switch self {
        case .celestial: "거리 = 트리 깊이 · 방위 = 서브트리 · 고도 = 레이어 · 바깥 = 최근"
        case .shells: "반지름 = 트리 깊이 · 각도 = 서브트리 · 높이 = 레이어"
        case .sphere: "구면 순서 = 경로 · 폴더 = 바깥 허브"
        case .treeRadial: "링 = 깊이 · 각도 = 파일 수 비례 · 높이 = 레이어"
        case .wall: "열·행 = 경로 순서 · 폴더 = 위 라벨"
        case .spiral: "높이·회전 = 경로 순서"
        }
    }

    /// Whether `ConstellationLayout.project` pushes along the 3-D direction from the centre (spherical styles)
    /// or along the horizontal direction around the vertical axis (disc / wall / helix styles).
    public var timeProjection: TimeProjection {
        switch self {
        case .celestial, .sphere: .spherical
        case .shells, .treeRadial, .wall, .spiral: .cylindrical
        }
    }
}

/// How the time dial displaces nodes. See `ConstellationLayout.project`.
public enum TimeProjection: String, Codable, Sendable, Hashable {
    /// Push along the horizontal direction away from the vertical axis through `center`, plus a 35 % lift
    /// (the original FR-2.7 rule; with `center == .zero` it is exactly the v1 projection).
    case cylindrical
    /// Push along the full 3-D direction away from `center`.
    case spherical
}
