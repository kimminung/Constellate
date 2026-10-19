import ConstellateKit
import SwiftUI

/// Roster with role badges, SharePlay controls and a demo "simulate member" button.
struct ParticipantsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("참가자", "Participants")).font(.headline)
                Spacer()
                Text(sessionLabel).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.participants) { participant in
                HStack(spacing: 10) {
                    Circle()
                        .fill(model.theme.avatarAccent.shiftedHue(by: participant.hueOffset).swiftUIColor)
                        .frame(width: 12, height: 12)
                    Text(participant.displayName + (participant.isLocal ? L(" (나)", " (you)") : ""))
                    Spacer()
                    Text(participant.role == .host ? L("호스트", "HOST") : L("참가자", "member"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(participant.role == .host ? model.theme.orbHalo.swiftUIColor.opacity(0.3) : Color.secondary.opacity(0.15), in: Capsule())
                }
            }
            Picker(L("모드", "Mode"), selection: Binding(get: { model.meetingMode }, set: { model.setMeetingMode($0) })) {
                ForEach(MeetingMode.allCases, id: \.self) { mode in Text(mode.name(model.language)).tag(mode) }
            }
            .pickerStyle(.segmented)
            HStack {
                Button { Task { await model.session.startSharing() } } label: {
                    Label(L("SharePlay 초대", "SharePlay"), systemImage: "shareplay")
                }
                Button { model.addSimulatedMember() } label: {
                    Label(L("가상 참가자 추가", "Add simulated member"), systemImage: "person.badge.plus")
                }
                if model.session.isSimulated {
                    Button(L("지우기", "Clear")) { model.session.removeSimulatedMembers() }
                }
            }
            .controlSize(.small)
        }
    }

    /// SharePlay state in the current language.
    private var sessionLabel: String {
        switch model.session.state {
        case .idle: L("공유 안 함", "Not sharing")
        case .activating: L("SharePlay 시작 중…", "Starting SharePlay…")
        case .shared(let n): L("SharePlay · \(n)명 연결", "SharePlay · \(n) connected")
        case .unavailable(let reason): L("SharePlay 사용 불가 · \(reason)", "SharePlay unavailable · \(reason)")
        }
    }
}
