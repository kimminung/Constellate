import ConstellateKit
import SwiftUI

/// Preset swatches + custom hue slider; shows the `validate()` verdict.
struct ThemePickerView: View {
    @Environment(AppModel.self) private var model
    @State private var hue: Double = 210
    @State private var applyTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("테마", "Theme")).font(.headline)
                Spacer()
                validationBadge
            }
            HStack(spacing: 10) {
                ForEach(ConstellateTheme.presets) { preset in
                    Button { model.setTheme(preset) } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().fill(LinearGradient(colors: [preset.skyTop.swiftUIColor, preset.skyHorizon.swiftUIColor], startPoint: .top, endPoint: .bottom))
                                Circle().fill(preset.orbHalo.swiftUIColor).scaleEffect(0.4)
                            }
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(model.theme.name == preset.name ? Color.primary : .clear, lineWidth: 2))
                            Text(themeDisplayName(preset.name)).font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(themeDisplayName(preset.name))
                }
            }
            HStack {
                Text(L("색조", "Hue")).font(.caption)
                Slider(value: $hue, in: 0...359, step: 1)
                Text("\(Int(hue))°").font(.caption.monospacedDigit()).frame(width: 40, alignment: .trailing)
            }
            .onChange(of: hue) {
                applyTask?.cancel()
                let h = hue
                applyTask = Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled else { return }
                    model.setTheme(.tinted(hue: h))
                }
            }
        }
    }

    private var validationBadge: some View {
        let violations = model.theme.validate()
        return HStack(spacing: 4) {
            Image(systemName: violations.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(violations.isEmpty ? Color.green : .orange)
            Text(violations.isEmpty
                 ? L("가독성 통과", "legible")
                 : L("규칙 \(violations.count)개 위반", "\(violations.count) rule\(violations.count == 1 ? "" : "s")"))
                .font(.caption)
        }
        .help(violations.map(\.description).joined(separator: "\n"))
    }
}
