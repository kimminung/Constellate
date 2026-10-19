import ConstellateKit
import SwiftUI

/// Guided-tour controls: step navigation, narration, follow-host.
struct TourBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let tour = model.tour, tour.steps.indices.contains(model.currentStep) {
            let step = tour.steps[model.currentStep]
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "figure.walk")
                    Text(tour.title).font(.headline)
                    Spacer()
                    Text("\(model.currentStep + 1) / \(tour.steps.count)").font(.caption.monospacedDigit())
                    Toggle(L("호스트 따라가기", "Follow host"), isOn: Binding(get: { model.followHost }, set: { model.setFollowHost($0) }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    Button { model.endTour() } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("투어 끝내기", "End tour"))
                }
                Text(step.title).font(.subheadline.weight(.semibold))
                Text(step.narration).font(.callout).lineLimit(3)
                HStack {
                    Button { model.previousStep() } label: { Label(L("이전", "Prev"), systemImage: "chevron.left") }
                        .disabled(model.currentStep == 0)
                    Button { model.nextStep() } label: { Label(L("다음", "Next"), systemImage: "chevron.right") }
                        .disabled(model.currentStep >= tour.steps.count - 1)
                    Spacer()
                    Button { model.summon(step.nodeID, reason: "tour") } label: { Label(L("출두", "Summon"), systemImage: "arrow.up.forward.app") }
                }
                .controlSize(.small)
            }
        }
    }
}
