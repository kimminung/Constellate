import ConstellateKit
import SwiftUI

/// Roster with role badges, SharePlay controls and a demo "simulate member" button.
struct ParticipantsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Participants · 참가자").font(.headline)
                Spacer()
                Text(model.session.state.label).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.participants) { participant in
                HStack(spacing: 10) {
                    Circle()
                        .fill(model.theme.avatarAccent.shiftedHue(by: participant.hueOffset).swiftUIColor)
                        .frame(width: 12, height: 12)
                    Text(participant.displayName + (participant.isLocal ? " (you)" : ""))
                    Spacer()
                    Text(participant.role == .host ? "HOST" : "member")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(participant.role == .host ? model.theme.orbHalo.swiftUIColor.opacity(0.3) : Color.secondary.opacity(0.15), in: Capsule())
                }
            }
            Picker("Mode", selection: Binding(get: { model.meetingMode }, set: { model.setMeetingMode($0) })) {
                ForEach(MeetingMode.allCases, id: \.self) { mode in Text(mode.rawValue.capitalized).tag(mode) }
            }
            .pickerStyle(.segmented)
            HStack {
                Button { Task { await model.session.startSharing() } } label: {
                    Label("SharePlay · 초대", systemImage: "shareplay")
                }
                Button { model.addSimulatedMember() } label: {
                    Label("Add simulated member", systemImage: "person.badge.plus")
                }
                if model.session.isSimulated {
                    Button("Clear") { model.session.removeSimulatedMembers() }
                }
                Toggle("Screenshot mode", isOn: Binding(get: { model.screenshotMode }, set: { model.screenshotMode = $0 }))
                    .toggleStyle(.button)
                    .help("Hide placeholders and toasts for clean captures")
            }
            .controlSize(.small)
        }
    }
}
