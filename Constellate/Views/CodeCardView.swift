import ConstellateKit
import SwiftUI

/// Syntax-highlighted source for one node, using the fixed code palette on the card background.
struct CodeCardView: View {
    @Environment(AppModel.self) private var model
    var nodeID: NodeID

    @State private var attributed: AttributedString?
    @State private var lineCount = 0
    /// True while there is more content to the right of the visible area.
    @State private var overflowsRight = false

    var body: some View {
        let palette = model.theme.code
        ScrollView([.vertical, .horizontal]) {
            if let attributed {
                // Monospaced, never wrapped: long lines scroll horizontally instead of clipping.
                Text(attributed)
                    .font(.system(.caption, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
                    .padding(12)
            } else {
                ProgressView().padding()
            }
        }
        .scrollIndicators(.visible, axes: .horizontal)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 2
        } action: { _, overflows in
            overflowsRight = overflows
        }
        .background(palette.cardBackground.swiftUIColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .trailing) {
            // Subtle right-edge fade hints that lines continue off-screen.
            if overflowsRight {
                LinearGradient(colors: [palette.cardBackground.withAlpha(0).swiftUIColor, palette.cardBackground.withAlpha(1).swiftUIColor],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 28)
                    .padding(.vertical, 1)
                    .padding(.bottom, 10)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.cardBorder.swiftUIColor))
        .accessibilityLabel("Source code, \(lineCount) lines")
        .task(id: nodeID) { await load(palette: palette) }
    }

    private func load(palette: CodePalette) async {
        attributed = nil
        guard let node = model.graph.node(nodeID) else { return }
        let graph = model.graph
        let root = model.projectRootURL
        let result = await Task.detached(priority: .userInitiated) { () -> (AttributedString, Int) in
            let source = SourceProvider.source(for: node, in: graph, projectRoot: root)
            let clipped = SourceProvider.previewLines(source, count: 400).joined(separator: "\n")
            return (SyntaxHighlighter.attributed(clipped, palette: palette, font: .system(.caption, design: .monospaced)), source.split(whereSeparator: \.isNewline).count)
        }.value
        attributed = result.0
        lineCount = result.1
    }
}
