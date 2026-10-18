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
                    relations(node)
                    pins(node)
                    actions(node)
                }
                .padding(16)
            }
            .navigationTitle(node.name)
        } else {
            ContentUnavailableView("Select a card", systemImage: "rectangle.on.rectangle.angled", description: Text("Tap a code card in the constellation or pick a node in the navigator."))
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
                Text(node.layer.rawValue)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(model.theme.color(for: node.layer).swiftUIColor.opacity(0.25), in: Capsule())
                Label(node.kind.rawValue, systemImage: "tag")
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
            Label("L\(lines.start)–\(lines.end) · \(lines.count) lines", systemImage: "number")
        } else if node.lineCount > 0 {
            Label("\(node.lineCount) lines", systemImage: "number")
        }
        if let date = node.modifiedAt {
            Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "clock")
        }
    }

    /// Top-3 nodes by `references` fan-in inside this folder/file.
    private func hubs(_ node: CodeNode) -> some View {
        let hubs = model.hubs(within: node.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Most referenced · 허브").font(.headline)
            if hubs.isEmpty {
                Text("Nothing inside is referenced yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(hubs, id: \.node.id) { hub in
                Button { model.select(hub.node.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: NodeRow.icon(for: hub.node.kind))
                            .foregroundStyle(model.theme.color(for: hub.node.layer).swiftUIColor)
                        Text(hub.node.name).lineLimit(1)
                        Spacer()
                        Text("\(hub.fanIn) refs").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func relations(_ node: CodeNode) -> some View {
        let out = model.graph.outgoing(from: node.id)
        let inc = model.graph.incoming(to: node.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Relations").font(.headline)
            if out.isEmpty && inc.isEmpty {
                Text("No relation edges.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(out.prefix(8).enumerated()), id: \.offset) { _, edge in
                relationRow(edge, outgoing: true)
            }
            ForEach(Array(inc.prefix(8).enumerated()), id: \.offset) { _, edge in
                relationRow(edge, outgoing: false)
            }
        }
    }

    private func relationRow(_ edge: CodeEdge, outgoing: Bool) -> some View {
        let other = outgoing ? edge.to : edge.from
        return Button {
            model.select(other)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: outgoing ? "arrow.right" : "arrow.left")
                    .foregroundStyle(model.theme.color(for: edge.kind).swiftUIColor)
                Text(edge.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                Text(model.graph.node(other)?.name ?? other.raw).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func pins(_ node: CodeNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Review pins · 핀").font(.headline)
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
                    .accessibilityLabel(pin.resolved ? "Reopen pin" : "Resolve pin")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.text).strikethrough(pin.resolved)
                        Text("\(pin.authorName) · \(pin.createdAt.formatted(date: .omitted, time: .shortened))" + (pin.line.map { " · line \($0)" } ?? ""))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if model.canDelete(pin) {
                        Button(role: .destructive) { model.deletePin(pin.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Delete pin")
                    }
                }
            }
            HStack {
                TextField("Add a review comment…", text: $pinText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addPin(node) }
                Button("Pin") { addPin(node) }.disabled(pinText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if model.pins.count > model.pins(for: node.id).count {
                Text("\(model.pins.count) pins in total across the project.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Markdown export: share sheet on iPad/visionOS, save panel (fileExporter) on macOS.
    @ViewBuilder
    private var exportControl: some View {
#if os(macOS)
        Button { showExporter = true } label: { Label("Export pins", systemImage: "square.and.arrow.up") }
            .controlSize(.small)
            .fileExporter(isPresented: $showExporter, item: model.pinsMarkdown, contentTypes: [.plainText], defaultFilename: model.pinsFilename) { result in
                if case .failure(let error) = result { model.statusMessage = error.localizedDescription }
            }
#else
        ShareLink(item: model.pinsMarkdown, subject: Text("Review pins"), message: Text(model.pinsFilename), preview: SharePreview(model.pinsFilename, image: Image(systemName: "pin.fill"))) {
            Label("Export pins", systemImage: "square.and.arrow.up")
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
            actionButton("Ask host · 설명", "sparkles") { Task { await model.askHostAboutSelection() } }
            actionButton("Review", "checklist") { Task { await model.reviewSelection() } }
            actionButton("Summon · 출두", "arrow.up.forward.app") { model.summon(node.id, reason: "inspector") }
            actionButton(model.pinnedBeacons.contains(node.id) ? "Unpin beacon" : "Beacon", "light.beacon.max") { model.togglePinnedBeacon(node.id) }
            if let cluster {
                actionButton(model.dockedClusterID == cluster.id ? "Undock" : "Dock host", "circle.dotted.circle") { model.toggleDock(cluster.id) }
            }
#if os(macOS) || os(visionOS)
            if nodeID == nil {
                actionButton("Open in window", "macwindow.on.rectangle") { openWindow(id: "inspector", value: node.id) }
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
