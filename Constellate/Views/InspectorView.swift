import ConstellateKit
import SwiftUI
import UniformTypeIdentifiers

/// Selected node: metadata, code card, relations, review pins and host actions.
struct InspectorView: View {
    @Environment(AppModel.self) private var model
#if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
#endif
    /// Explicit node (inspector window) or nil to follow the selection.
    var nodeID: NodeID?
    @State private var pinText = ""
    @State private var showExporter = false

    private var node: CodeNode? { model.node(nodeID ?? model.selectedNodeID) }

    var body: some View {
        if let node {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(node)
                    CodeCardView(nodeID: node.id)
                        .frame(minHeight: 220, maxHeight: 420)
                    if node.kind == .folder || node.kind == .file || node.kind == .module {
                        hubs(node)
                    }
                    if node.kind != .folder && node.kind != .module {
                        coupling(node)
                    }
                    relations(node)
                    pins(node)
                    actions(node)
                }
                .padding(16)
            }
            .navigationTitle(node.name)
        } else {
            ContentUnavailableView(L("카드를 선택하세요", "Select a card"), systemImage: "rectangle.on.rectangle.angled",
                                   description: Text(L("별자리에서 코드 카드를 탭하거나 내비게이터에서 노드를 고르세요.", "Tap a code card in the constellation or pick a node in the navigator.")))
        }
    }

    private func header(_ node: CodeNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: NodeRow.icon(for: node.kind))
                Text(node.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Spacer(minLength: 0)
            }
            // Badges on their own line so the title never competes with them at 300 pt.
            HStack(spacing: 8) {
                Text(node.layer.name(model.language))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(model.theme.color(for: node.layer).swiftUIColor.opacity(0.25), in: Capsule())
                if let role = node.role, !role.style.label.isEmpty {
                    Label(role.style.label, systemImage: role.style.symbol)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .foregroundStyle(role.style.color.swiftUIColor)
                        .background(role.style.color.swiftUIColor.opacity(0.16), in: Capsule())
                        .help(L("역할 (별자리에서 별의 모양)", "Role (the star's shape in the constellation)"))
                }
                Label(node.kind.name(model.language), systemImage: "tag")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(node.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { metadata(node) }
                VStack(alignment: .leading, spacing: 4) { metadata(node) }
            }
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if !node.tags.isEmpty {
                FlowTags(tags: node.tags.sorted())
            }
        }
    }

    @ViewBuilder
    private func metadata(_ node: CodeNode) -> some View {
        if let lines = node.lines {
            Label(L("L\(lines.start)–\(lines.end) · \(lines.count)줄", "L\(lines.start)–\(lines.end) · \(lines.count) lines"), systemImage: "number")
        } else if node.lineCount > 0 {
            Label(L("\(node.lineCount)줄", "\(node.lineCount) lines"), systemImage: "number")
        }
        if let date = node.modifiedAt {
            Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "clock")
        }
    }

    /// Top-3 nodes by `references` fan-in inside this folder/file.
    private func hubs(_ node: CodeNode) -> some View {
        let hubs = model.hubs(within: node.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text(L("허브 · 가장 많이 참조됨", "Most referenced")).font(.headline)
            if hubs.isEmpty {
                Text(L("아직 안에서 참조되는 것이 없습니다.", "Nothing inside is referenced yet.")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(hubs, id: \.node.id) { hub in
                Button { model.select(hub.node.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: NodeRow.icon(for: hub.node.kind))
                            .foregroundStyle(model.theme.color(for: hub.node.layer).swiftUIColor)
                        Text(hub.node.name).lineLimit(1)
                        Spacer()
                        Text(L("\(hub.fanIn)회 참조", "\(hub.fanIn) refs")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Martin's coupling metrics for the node's file (GraphInsights): who leans on it, what it leans on, how far a
    /// change would ripple, and whether it is tangled in a dependency cycle.
    private func coupling(_ node: CodeNode) -> some View {
        let m = model.metrics(for: node.id)
        let cycle = model.insights.cycleMembers(of: node.id)
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("결합도", "Coupling")).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow {
                    metric("\(m.fanIn)", L("의존받음 (Fan-in)", "Fan-in"), L("이 파일에 의존하는 파일 수 (Ca)", "Files that depend on this file (Ca)"))
                    metric("\(m.fanOut)", L("의존함 (Fan-out)", "Fan-out"), L("이 파일이 의존하는 파일 수 (Ce)", "Files this file depends on (Ce)"))
                }
                GridRow {
                    metric(m.instability.map { String(format: "%.2f", $0) } ?? "–", L("불안정도", "Instability"),
                           L("I = Ce / (Ca + Ce): 0 = 안정된 기반, 1 = 자유롭게 바꿔도 됨", "I = Ce / (Ca + Ce): 0 = stable foundation, 1 = free to change"))
                    metric("\(m.impact)", L("영향 범위", "Impact"),
                           L("이 파일에 간접적으로 의존하는 파일 수 — 변경이 번질 수 있는 범위", "Files that transitively depend on this one — what a change could ripple into"))
                }
            }
            if !cycle.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(EdgeBatchKey.cycleColor.swiftUIColor)
                    Text(L("다른 파일 \(cycle.count - 1)개와 순환 의존 관계", "In a dependency cycle with \(cycle.count - 1) other file\(cycle.count == 2 ? "" : "s")"))
                        .font(.caption)
                    Spacer(minLength: 4)
                    Button(L("강조", "Highlight")) { model.setHighlights(cycle) }
                        .controlSize(.small)
                        .help(L("순환에 속한 모든 파일을 강조합니다. 관계 표시가 켜져 있으면 고리가 빨갛게 그려집니다", "Highlight every file in the cycle; with Relations on, the loop is drawn in red"))
                }
            }
        }
    }

    private func metric(_ value: String, _ label: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .help(help)
        .accessibilityElement(children: .combine)
        .accessibilityHint(help)
    }

    /// Relations grouped by kind and direction ("Presents", "Observed by" …), members folded into the node.
    private func relations(_ node: CodeNode) -> some View {
        let groups = model.relationGroups(for: node.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("관계", "Relations")).font(.headline)
                Spacer()
                Button { model.cycleRelationMode() } label: {
                    Label(model.relationMode.name(model.language), systemImage: model.relationMode.symbol).font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L("별자리에 그려지는 관계 (탭하면 끔 → 선택 → 전체 순환)", "Relations drawn in the constellation (tap to cycle off → focus → all)"))
            }
            if groups.isEmpty {
                Text(L("이 노드에서 나가는 관계가 없습니다.", "No relations leave this node.")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                relationGroup(group)
            }
        }
    }

    private func relationGroup(_ group: RelationGroup) -> some View {
        let style = group.relation.style
        let hidden = model.hiddenRelations.contains(group.relation)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                RelationSwatch(color: style.color.swiftUIColor, dashed: style.dashed, flow: style.flow)
                    .frame(width: 28, height: 10)
                    .scaleEffect(x: group.outgoing ? 1 : -1, y: 1)   // incoming: the arrow points back at this node
                Text(group.relation.phrase(outgoing: group.outgoing, language: model.language)).font(.caption.weight(.semibold))
                if hidden {
                    Image(systemName: "eye.slash").font(.caption2).foregroundStyle(.secondary)
                        .help(L("별자리에서 숨김 (범례)", "Hidden in the constellation (legend)"))
                }
                Spacer(minLength: 4)
                Text(group.total.formatted()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 6) {
                ForEach(group.nodes, id: \.self) { other in
                    Button { model.select(other) } label: {
                        Text(model.graph.node(other)?.name ?? other.raw)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(style.color.swiftUIColor.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if group.total > group.nodes.count {
                    Text("+\(group.total - group.nodes.count)")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
        .opacity(hidden ? 0.6 : 1)
    }

    private func pins(_ node: CodeNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("리뷰 핀", "Review pins")).font(.headline)
                Spacer()
                if !model.pins.isEmpty { exportControl }
            }
            ForEach(model.pins(for: node.id)) { pin in
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        model.resolvePin(pin.id, resolved: !pin.resolved)
                    } label: {
                        Image(systemName: pin.resolved ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(pin.resolved ? Color.green : model.theme.beacon.swiftUIColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pin.resolved ? L("핀 다시 열기", "Reopen pin") : L("핀 해결", "Resolve pin"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.text).strikethrough(pin.resolved)
                        Text("\(pin.authorName) · \(pin.createdAt.formatted(date: .omitted, time: .shortened))" + (pin.line.map { L(" · \($0)행", " · line \($0)") } ?? ""))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if model.canDelete(pin) {
                        Button(role: .destructive) { model.deletePin(pin.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(L("핀 삭제", "Delete pin"))
                    }
                }
            }
            HStack {
                TextField(L("리뷰 코멘트 추가…", "Add a review comment…"), text: $pinText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addPin(node) }
                Button(L("핀", "Pin")) { addPin(node) }.disabled(pinText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if model.pins.count > model.pins(for: node.id).count {
                Text(L("프로젝트 전체 핀 \(model.pins.count)개.", "\(model.pins.count) pins in total across the project.")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Markdown export: share sheet on iPad/visionOS, save panel (fileExporter) on macOS.
    @ViewBuilder
    private var exportControl: some View {
#if os(macOS)
        Button { showExporter = true } label: { Label(L("핀 내보내기", "Export pins"), systemImage: "square.and.arrow.up") }
            .controlSize(.small)
            .fileExporter(isPresented: $showExporter, item: model.pinsMarkdown, contentTypes: [.plainText], defaultFilename: model.pinsFilename) { result in
                if case .failure(let error) = result { model.statusMessage = error.localizedDescription }
            }
#else
        ShareLink(item: model.pinsMarkdown, subject: Text(L("리뷰 핀", "Review pins")), message: Text(model.pinsFilename), preview: SharePreview(model.pinsFilename, image: Image(systemName: "pin.fill"))) {
            Label(L("핀 내보내기", "Export pins"), systemImage: "square.and.arrow.up")
        }
        .controlSize(.small)
#endif
    }

    private func addPin(_ node: CodeNode) {
        let text = pinText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        model.addPin(nodeID: node.id, text: text)
        pinText = ""
    }

    /// 2-column grid; labels never wrap or hyphenate.
    private func actions(_ node: CodeNode) -> some View {
        let cluster = model.clusters.first { $0.memberNodeIDs.contains(node.id) }
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            actionButton(L("호스트에게 설명 요청", "Ask host"), "sparkles") { Task { await model.askHostAboutSelection() } }
            actionButton(L("리뷰", "Review"), "checklist") { Task { await model.reviewSelection() } }
            actionButton(L("출두", "Summon"), "arrow.up.forward.app") { model.summon(node.id, reason: "inspector") }
            actionButton(model.pinnedBeacons.contains(node.id) ? L("비콘 고정 해제", "Unpin beacon") : L("비콘", "Beacon"), "light.beacon.max") { model.togglePinnedBeacon(node.id) }
            if let cluster {
                actionButton(model.dockedClusterID == cluster.id ? L("호스트 분리", "Undock") : L("호스트 도킹", "Dock host"), "circle.dotted.circle") { model.toggleDock(cluster.id) }
            }
#if os(macOS) || os(visionOS)
            if nodeID == nil {
                actionButton(L("새 창에서 열기", "Open in window"), "macwindow.on.rectangle") { openWindow(id: "inspector", value: node.id) }
            }
#endif
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func actionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Wrapping tag chips: at most `visibleLimit` chips, then a "+N" chip.
struct FlowTags: View {
    var tags: [String]
    var visibleLimit = 6

    var body: some View {
        let shown = Array(tags.prefix(visibleLimit))
        let extra = tags.count - shown.count
        FlowLayout(spacing: 6) {
            ForEach(shown, id: \.self) { tag in
                chip(tag)
            }
            if extra > 0 {
                chip("+\(extra)").help(tags.dropFirst(visibleLimit).joined(separator: ", "))
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

/// Minimal left-to-right wrapping layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: width.isFinite ? width : maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Stand-alone inspector window (`WindowGroup(id: "inspector", for: NodeID.self)`).
struct CodeInspectorWindow: View {
    @Environment(AppModel.self) private var model
    var nodeID: NodeID?

    var body: some View {
        NavigationStack {
            InspectorView(nodeID: nodeID ?? model.selectedNodeID)
        }
        .frame(minWidth: 360, minHeight: 480)
    }
}
