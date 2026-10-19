import SwiftUI

/// Push-to-talk toggle with the live partial transcript.
struct VoiceButton: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        let listening = model.speech.isActive
        VStack(alignment: .leading, spacing: 4) {
            Button {
                model.toggleVoice()
            } label: {
                if compact {
                    Image(systemName: listening ? "mic.fill" : "mic")
                        .symbolEffect(.variableColor.iterative, isActive: listening)
                } else {
                    Label(listening ? L("듣는 중…", "Listening…") : L("음성", "Voice"), systemImage: listening ? "mic.fill" : "mic")
                        .symbolEffect(.variableColor.iterative, isActive: listening)
                }
            }
            .tint(listening ? .red : nil)
            .help(model.speech.stateLabel)
            .accessibilityLabel(listening ? L("듣기 중지", "Stop listening") : L("듣기 시작", "Start listening"))
            if !compact, !model.speech.liveTranscript.isEmpty {
                Text(model.speech.liveTranscript).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if !compact, case .unavailable(let reason) = model.speech.state {
                Text(reason).font(.caption2).foregroundStyle(.orange)
            }
        }
    }
}
