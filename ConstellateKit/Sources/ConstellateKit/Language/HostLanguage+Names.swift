import Foundation

// Display names in one language at a time. The bilingual `label` properties ("천구 · Celestial") stay for
// callers that want both; the app's chrome uses these so Korean is shown alone and English only when chosen.

public extension ArchitectureLayer {
    func name(_ language: HostLanguage) -> String {
        switch self {
        case .presentation: language.pick("프레젠테이션", "presentation")
        case .domain: language.pick("도메인", "domain")
        case .data: language.pick("데이터", "data")
        case .infrastructure: language.pick("인프라", "infrastructure")
        case .test: language.pick("테스트", "test")
        case .unknown: language.pick("일반", "general")
        }
    }
}

public extension NodeKind {
    func name(_ language: HostLanguage) -> String {
        switch self {
        case .module: language.pick("모듈", "module")
        case .folder: language.pick("폴더", "folder")
        case .file: language.pick("파일", "file")
        case .type: language.pick("타입", "type")
        case .extensionDecl: "extension"
        case .function: language.pick("함수", "function")
        case .property: language.pick("프로퍼티", "property")
        }
    }
}

public extension EdgeKind {
    func name(_ language: HostLanguage) -> String {
        switch self {
        case .contains: language.pick("포함", "contains")
        case .imports: "import"
        case .references: language.pick("참조", "references")
        case .inherits: language.pick("상속", "inherits")
        case .calls: language.pick("호출", "calls")
        }
    }
}

public extension ClusterGranularity {
    func name(_ language: HostLanguage) -> String {
        switch self {
        case .folder: language.pick("폴더", "Folder")
        case .file: language.pick("파일", "File")
        case .type: language.pick("타입", "Type")
        case .feature: language.pick("기능", "Feature")
        }
    }
}

public extension MeetingMode {
    func name(_ language: HostLanguage) -> String {
        switch self {
        case .analysis: language.pick("분석", "Analysis")
        case .review: language.pick("리뷰", "Review")
        case .lecture: language.pick("강의", "Lecture")
        }
    }
}

public extension LayoutStyle {
    /// "천구" / "Celestial".
    func name(_ language: HostLanguage) -> String {
        switch self {
        case .celestial: language.pick("천구", "Celestial")
        case .shells: language.pick("셸", "Shells")
        case .sphere: language.pick("구", "Sphere")
        case .treeRadial: language.pick("트리 방사형", "Tree radial")
        case .wall: language.pick("벽", "Wall")
        case .spiral: language.pick("나선", "Spiral")
        }
    }

    /// What each spatial axis means, in one language.
    func axes(_ language: HostLanguage) -> String {
        guard language == .english else { return axes }
        switch self {
        case .celestial: return "distance = tree depth · azimuth = subtree · elevation = layer · outward = recent"
        case .shells: return "radius = tree depth · angle = subtree · height = layer"
        case .sphere: return "sphere order = path · folders = outer hubs"
        case .treeRadial: return "ring = depth · angle ∝ file count · height = layer"
        case .wall: return "columns·rows = path order · folders = labels above"
        case .spiral: return "height·turn = path order"
        }
    }
}

public extension RelationDisplayMode {
    func name(_ language: HostLanguage) -> String {
        switch self {
        case .off: language.pick("관계 끔", "Off")
        case .focus: language.pick("선택", "Focus")
        case .all: language.pick("전체", "All")
        }
    }
}

public extension RelationStyle {
    /// "상태 흐름" / "Binds".
    func name(_ language: HostLanguage) -> String { language.pick(labelKo, labelEn) }
}

public extension RelationKind {
    /// One-line explanation of the direction, in one language (`style.hint` is Korean).
    func hint(_ language: HostLanguage) -> String {
        guard language == .english else { return style.hint }
        switch self {
        case .conforms: return "type → protocol / superclass"
        case .extends: return "extension → original type"
        case .composes: return "parent view → child view"
        case .presents: return "sheet / NavigationLink / present → destination"
        case .binds: return "data source → observing view"
        case .creates: return "creator → created type"
        case .delegates: return "implementation → protocol"
        case .notifies: return "post → observe"
        case .uses: return "use → definition"
        case .imports: return "file → module / top-level folder"
        case .calls: return "function → function"
        }
    }

    /// Inspector heading for one direction in one language ("띄우는 화면" / "Presents").
    /// `phrase(outgoing:)` keeps the bilingual form that `CodeSearcher` reasons are built from.
    func phrase(outgoing: Bool, language: HostLanguage) -> String {
        let parts = phrase(outgoing: outgoing).components(separatedBy: " · ")
        switch language {
        case .english: return parts.first ?? rawValue
        case .korean: return parts.count > 1 ? parts[1] : (parts.first ?? rawValue)
        }
    }
}
