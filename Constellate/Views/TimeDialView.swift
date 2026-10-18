import SwiftUI

/// −1 … 1 time dial. Negative pulls older code toward the viewer, positive pushes newer code outward.
struct TimeDialView: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        let binding = Binding<Float>(get: { model.timeDial }, set: { model.setTimeDial($0) })
        VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            if !compact {
                HStack {
                    Text("Time dial · 타임 다이얼").font(.headline)
                    Spacer()
                    Button("Reset") { model.setTimeDial(0) }.controlSize(.small).disabled(model.timeDial == 0)
                }
            }
            HStack(spacing: 8) {
                Text("Older").font(.caption2).foregroundStyle(.secondary)
                Slider(value: binding, in: -1...1)
                Text("Newer").font(.caption2).foregroundStyle(.secondary)
            }
            if !compact {
                Text(model.timeDial == 0 ? "Now · pure spatial layout" : String(format: "%+.2f", model.timeDial))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}
