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
                    Label(listening ? "Listening… · 듣는 중" : "Voice · 음성", systemImage: listening ? "mic.fill" : "mic")
                        .symbolEffect(.variableColor.iterative, isActive: listening)
                }
            }
            .tint(listening ? .red : nil)
            .help(model.speech.state.label)
            .accessibilityLabel(listening ? "Stop listening" : "Start listening")
            if !compact, !model.speech.liveTranscript.isEmpty {
                Text(model.speech.liveTranscript).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if !compact, case .unavailable(let reason) = model.speech.state {
                Text(reason).font(.caption2).foregroundStyle(.orange)
            }
        }
    }
}
