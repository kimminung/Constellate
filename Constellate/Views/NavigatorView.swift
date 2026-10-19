import ConstellateKit
import SwiftUI

/// Tree outline of the project with kind icons and a search field.
/// Custom outline (not `List(children:)`) so indentation stays at 12 pt per level and deep rows keep their names.
struct NavigatorView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selection: NodeID?
    @State private var expanded: Set<NodeID> = []
    @State private var rows: [Row] = []
    @FocusState private var searchFocused: Bool

    static let indentPerLevel: CGFloat = 12

    private struct Row: Identifiable, Hashable {
        var id: NodeID
        var node: CodeNode
        var depth: Int
        var hasChildren: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("코드 찾기", "Find code"), text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = model.search(query, limit: 1).first { model.summon(first.nodeID, reason: query) }
                    }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("검색어 지우기", "Clear search"))
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .top], 10)

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                List(rows, selection: $selection) { row in
                    outlineRow(row)
                        .tag(row.id)
                        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                }
                .listStyle(.sidebar)
            } else {
                List(model.search(query), selection: $selection) { hit in
                    if let node = model.graph.node(hit.nodeID) {
                        VStack(alignment: .leading, spacing: 2) {
                            NodeRow(node: node)
                            Text(hit.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .tag(hit.nodeID)
                    }
                }
            }
        }
        .onChange(of: selection) { if let selection { model.select(selection) } }
        .onChange(of: model.selectedNodeID) {
            selection = model.selectedNodeID
            revealSelection()
        }
        .onChange(of: model.sceneRevision, initial: true) { resetOutline() }
        .onChange(of: model.searchFocusToken) { searchFocused = true }
    }

    private func outlineRow(_ row: Row) -> some View {
        HStack(spacing: 4) {
            Spacer().frame(width: CGFloat(row.depth) * Self.indentPerLevel)
            if row.hasChildren {
                Button {
                    toggle(row.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(expanded.contains(row.id) ? 90 : 0))
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(expanded.contains(row.id) ? L("\(row.node.name) 접기", "Collapse \(row.node.name)") : L("\(row.node.name) 펼치기", "Expand \(row.node.name)"))
            } else {
                Spacer().frame(width: 14)
            }
            NodeRow(node: row.node, compact: row.depth >= 3)
        }
        .contentShape(Rectangle())
    }

    private func toggle(_ id: NodeID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        rebuildRows()
    }

    private func resetOutline() {
        expanded = []
        if let root = model.graph.root {
            expanded.insert(root.id)
            for child in model.graph.children(of: root.id) { expanded.insert(child.id) }
        }
        rebuildRows()
    }

    /// Expands ancestors of the selected node so it is visible in the outline.
    private func revealSelection() {
        guard let id = model.selectedNodeID else { return }
        var changed = false
        for ancestor in model.graph.ancestors(of: id) where !expanded.contains(ancestor.id) {
            expanded.insert(ancestor.id)
            changed = true
        }
        if changed { rebuildRows() }
    }

    private func rebuildRows() {
        let graph = model.graph
        var out: [Row] = []
        func visit(_ node: CodeNode, depth: Int) {
            let kids = graph.children(of: node.id)
                .filter { $0.kind.isSpatial || depth < 3 }
                .sorted { ($0.kind.order, $0.name) < ($1.kind.order, $1.name) }
            out.append(Row(id: node.id, node: node, depth: depth, hasChildren: !kids.isEmpty))
            guard expanded.contains(node.id) else { return }
            for kid in kids { visit(kid, depth: depth + 1) }
        }
        if let root = graph.root { visit(root, depth: 0) }
        rows = out
    }
}

struct NodeRow: View {
    @Environment(AppModel.self) private var model
    var node: CodeNode
    /// Smaller font for deep levels (3+).
    var compact = false

    var body: some View {
        // Name wins the width fight; the line-count badge appears only when it fits.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                icon
                name
                Spacer(minLength: 6)
                if node.lineCount > 0 {
                    Text("\(node.lineCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
            }
            HStack(spacing: 6) {
                icon
                name
            }
        }
    }

    private var icon: some View {
        Image(systemName: Self.icon(for: node.kind))
            .font(compact ? .caption : .body)
            .foregroundStyle(model.theme.color(for: node.layer).swiftUIColor)
            .frame(width: 16)
    }

    private var name: some View {
        Text(node.name)
            .font(compact ? .subheadline : .body)
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(1)
    }

    static func icon(for kind: NodeKind) -> String {
        switch kind {
        case .module: "shippingbox"
        case .folder: "folder"
        case .file: "doc.text"
        case .type: "cube"
        case .extensionDecl: "puzzlepiece.extension"
        case .function: "function"
        case .property: "circle.hexagongrid"
        }
    }
}
