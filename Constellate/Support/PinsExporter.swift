import ConstellateKit
import Foundation

/// Renders review pins as Markdown for sharing / saving, in the app's language.
nonisolated enum PinsExporter {

    static func markdown(pins: [ReviewPin], graph: CodeGraph, date: Date = .now, language: HostLanguage = .appDefault) -> String {
        let day = date.formatted(date: .long, time: .shortened)
        var out = language.pick("# 리뷰 — \(graph.projectName) — \(day)\n\n", "# Review — \(graph.projectName) — \(day)\n\n")
        let open = pins.filter { !$0.resolved }.count
        out += language.pick(
            "핀 \(pins.count)개 · 열림 \(open) · 해결 \(pins.count - open)\n\n",
            "\(pins.count) pin\(pins.count == 1 ? "" : "s") · \(open) open · \(pins.count - open) resolved\n\n")

        let grouped = Dictionary(grouping: pins, by: \.nodeID)
        let orderedNodes = grouped.keys.sorted { lhs, rhs in
            (graph.node(lhs)?.path ?? lhs.raw) < (graph.node(rhs)?.path ?? rhs.raw)
        }
        for nodeID in orderedNodes {
            let node = graph.node(nodeID)
            let title = node?.name ?? nodeID.raw
            let path = node?.path ?? nodeID.raw
            out += "## \(title)\n\n`\(path)`"
            if let lines = node?.lines { out += " · L\(lines.start)–\(lines.end)" }
            out += "\n\n"
            for pin in (grouped[nodeID] ?? []).sorted(by: { $0.createdAt < $1.createdAt }) {
                let box = pin.resolved ? "[x]" : "[ ]"
                let line = pin.line.map { language.pick(" (\($0)행)", " (line \($0))") } ?? ""
                let when = pin.createdAt.formatted(date: .abbreviated, time: .shortened)
                out += "- \(box) \(pin.text)\(line) — _\(pin.authorName), \(when)_\n"
            }
            out += "\n"
        }
        return out
    }

    static func suggestedFilename(for graph: CodeGraph, date: Date = .now, language: HostLanguage = .appDefault) -> String {
        let stamp = date.formatted(.iso8601.year().month().day())
        return language.pick("리뷰-\(graph.projectName)-\(stamp).md", "Review-\(graph.projectName)-\(stamp).md")
    }
}
