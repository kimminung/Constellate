import ConstellateKit
import SwiftUI

// MARK: - Layout style

/// Constellation shape picker with the meaning of each spatial axis underneath (so the space stays readable).
struct LayoutStylePicker: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        let selection = Binding(get: { model.layoutStyle }, set: { model.setLayoutStyle($0) })
        if compact {
            Picker(L("배치", "Layout"), selection: selection) {
                ForEach(LayoutStyle.allCases) { style in
                    Label(style.name(model.language), systemImage: style.symbol).tag(style)
                }
            }
            .pickerStyle(.inline)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Picker(L("배치", "Layout"), selection: selection) {
                    ForEach(LayoutStyle.allCases) { style in
                        Label(style.name(model.language), systemImage: style.symbol).tag(style)
                    }
                }
                .pickerStyle(.menu)
                Text(model.layoutStyle.axes(model.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Relation mode

/// Off / focus / all — the portfolio's `L` cycle.
struct RelationModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker(L("관계", "Relations"), selection: Binding(get: { model.relationMode }, set: { model.setRelationMode($0) })) {
            ForEach(RelationDisplayMode.allCases) { mode in
                Label(mode.name(model.language), systemImage: mode.symbol).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - Legend

/// Every relation kind with its colour, line style and count; tap a row to hide / show that kind.
/// Colours are fixed across themes (`RelationKind.style`), so the legend never changes meaning.
struct RelationLegendView: View {
    @Environment(AppModel.self) private var model
    var showsModePicker = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsModePicker { RelationModePicker() }
            ForEach(RelationKind.legendOrder, id: \.self) { kind in
                row(kind)
            }
            HStack {
                Text(model.relationMode == .focus
                     ? L("카드를 선택하면 그 관계가 보입니다", "Select a card to see its relations")
                     : L("행을 누르면 숨겨집니다", "Tap a row to hide it"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.hiddenRelations.isEmpty {
                    Button(L("모두 표시", "Show all")) { model.showAllRelations() }
                        .font(.caption)
                }
            }
        }
    }

    private func row(_ kind: RelationKind) -> some View {
        let style = kind.style
        let hidden = model.hiddenRelations.contains(kind)
        let count = model.relationTotals[kind] ?? 0
        let language = model.language
        return Button {
            model.toggleRelation(kind)
        } label: {
            HStack(spacing: 10) {
                RelationSwatch(color: style.color.swiftUIColor, dashed: style.dashed, flow: style.flow)
                    .frame(width: 38, height: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(style.name(language)).font(.callout.weight(.medium))
                    Text(kind.hint(language)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: hidden ? "eye.slash" : "eye")
                    .font(.caption)
                    .foregroundStyle(hidden ? .secondary : .primary)
            }
            .opacity(hidden || count == 0 ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("\(style.labelKo) 관계, \(count)개", "\(style.labelEn) relations, \(count)"))
        .accessibilityValue(hidden ? L("숨김", "hidden") : L("표시", "shown"))
        .help(kind.hint(language))
    }
}

/// A short curved stroke drawn like the 3-D edge: dashed for type-system kinds, with an arrowhead for flow kinds.
struct RelationSwatch: View {
    var color: Color
    var dashed: Bool
    var flow: Bool

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 1, y: size.height * 0.75))
            path.addQuadCurve(to: CGPoint(x: size.width - (flow ? 6 : 1), y: size.height * 0.75), control: CGPoint(x: size.width / 2, y: 0))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: dashed ? [4, 3] : []))
            if flow {
                var head = Path()
                let tip = CGPoint(x: size.width - 0.5, y: size.height * 0.8)
                head.move(to: tip)
                head.addLine(to: CGPoint(x: tip.x - 7, y: tip.y - 5))
                head.addLine(to: CGPoint(x: tip.x - 6, y: tip.y + 3))
                head.closeSubpath()
                context.fill(head, with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Toolbar button: tap cycles off → focus → all (⌘L); the chevron opens the legend.
struct RelationToolbarControl: View {
    @Environment(AppModel.self) private var model
    @State private var showLegend = false

    var body: some View {
        HStack(spacing: 2) {
            Button { model.cycleRelationMode() } label: {
                Label(model.relationMode.name(model.language), systemImage: model.relationMode.symbol)
            }
            .modifier(TouchKeyboardShortcut(key: "l"))
            .help(L("관계: \(model.relationMode.name(model.language)) (⌘L로 끔 → 선택 → 전체 순환)",
                    "Relations: \(model.relationMode.name(model.language)) (⌘L cycles off → focus → all)"))
            Button { showLegend.toggle() } label: {
                Label(L("범례", "Legend"), systemImage: "list.bullet.rectangle")
            }
            .help(L("관계 범례", "Relation legend"))
            .popover(isPresented: $showLegend) {
                ScrollView {
                    RelationLegendView()
                        .padding(16)
                }
                .frame(minWidth: 340, idealWidth: 360, minHeight: 420)
            }
        }
    }
}

/// ⌘-shortcut on iPad keyboards; on the Mac the same command lives in the menu bar (ConstellateCommands).
private struct TouchKeyboardShortcut: ViewModifier {
    let key: KeyEquivalent

    func body(content: Content) -> some View {
#if os(macOS)
        content
#else
        content.keyboardShortcut(key, modifiers: .command)
#endif
    }
}
