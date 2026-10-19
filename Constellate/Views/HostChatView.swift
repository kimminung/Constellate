import ConstellateKit
import SwiftUI

/// Transcript with the host AI + text field + mic button.
struct HostChatView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HostOrbGlyph(presence: model.hostPresence, color: model.theme.orbHalo.swiftUIColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("호스트 AI", "Host AI")).font(.headline)
                    Text(model.hostStateLabel + " · " + model.hostAI.backendLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if model.dockedClusterID != nil {
                    Button(L("분리", "Undock")) { model.undockHost() }.controlSize(.small)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.hostTranscript) { entry in
                            TranscriptBubble(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: model.hostTranscript.count) {
                    if let last = model.hostTranscript.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            if !model.speech.liveTranscript.isEmpty {
                Text("“\(model.speech.liveTranscript)”").font(.callout.italic()).foregroundStyle(.secondary)
            }
            HStack {
                TextField(L("질문하거나 말하세요: 찾아 / 설명 / 들어가 / 투어 …", "Ask, or say: find / explain / dock / tour …"), text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button(action: send) { Image(systemName: "paperplane.fill") }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel(L("보내기", "Send"))
                VoiceButton(compact: true)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await model.handleVoice(text) }
    }
}

struct TranscriptBubble: View {
    @Environment(AppModel.self) private var model
    var entry: AppModel.TranscriptEntry

    var body: some View {
        HStack {
            if entry.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .font(entry.role == .system ? .caption : .callout)
                    .foregroundStyle(entry.role == .system ? .secondary : .primary)
                    .textSelection(.enabled)
                if !entry.nodeIDs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(entry.nodeIDs, id: \.raw) { id in
                                if let node = model.graph.node(id) {
                                    Button(node.name) { model.summon(id, reason: "chat") }
                                        .font(.caption2)
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
            if entry.role != .user { Spacer(minLength: 40) }
        }
    }

    private var background: AnyShapeStyle {
        switch entry.role {
        case .user: AnyShapeStyle(.tint.opacity(0.25))
        case .host: AnyShapeStyle(model.theme.orbHalo.swiftUIColor.opacity(0.18))
        case .system: AnyShapeStyle(.clear)
        }
    }
}
