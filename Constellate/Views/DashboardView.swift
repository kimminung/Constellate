import ConstellateKit
import SwiftUI
import UniformTypeIdentifiers

/// Root window. visionOS: a glass control panel next to the immersive space.
/// iPad / Mac: three-column split (navigator | viewport | inspector).
struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
#if os(visionOS)
            VisionDashboard()
#else
            SplitDashboard()
#endif
        }
        .fileImporter(isPresented: $model.showProjectImporter, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await model.openProject(url: url) }
            }
        }
    }
}

// MARK: - Shared header

struct ProjectHeaderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundStyle(model.theme.orbHalo.swiftUIColor)
                Text(model.graph.projectName).font(.title2.weight(.semibold))
                Spacer()
                Button {
                    model.showProjectImporter = true
                } label: {
                    Label("Open Project · 열기", systemImage: "folder")
                }
                .disabled(model.isIngesting)
                Button("Sample") { model.loadSample() }
            }
            let s = model.stats
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    StatPill(value: s.fileCount, label: "files")
                    StatPill(value: s.totalLines, label: "lines")
                    StatPill(value: s.countsByKind[.type] ?? 0, label: "types")
                    StatPill(value: s.countsByKind[.function] ?? 0, label: "functions")
                    StatPill(value: model.clusters.count, label: "orbs")
                    Divider().frame(height: 28)
                    ForEach(EdgeKind.allCases.filter { $0 != .contains }, id: \.self) { kind in
                        StatPill(value: s.countsByEdgeKind[kind] ?? 0, label: kind.rawValue, tint: model.theme.color(for: kind).swiftUIColor)
                    }
                }
            }
            if let oldest = s.oldestModified, let newest = s.newestModified {
                Label("\(oldest.formatted(date: .abbreviated, time: .omitted)) → \(newest.formatted(date: .abbreviated, time: .omitted))", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let status = model.statusMessage {
                Text(status).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            if model.isIngesting {
                ProgressView(model.ingestProgress.map { "\($0.filesParsed) parsed · \($0.currentPath)" } ?? "Reading…")
                    .font(.footnote)
            }
        }
    }
}

struct StatPill: View {
    var value: Int
    var label: String
    var tint: Color? = nil
    var body: some View {
        VStack(spacing: 1) {
            Text(value.formatted()).font(.headline.monospacedDigit()).foregroundStyle(tint ?? .primary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 52)
    }
}

// MARK: - visionOS

#if os(visionOS)
private struct VisionDashboard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ProjectHeaderView()
                    immersiveButton
                    hostStatus
                    GranularityPicker()
                    TimeDialView()
                    ThemePickerView()
                    ParticipantsView()
                    if model.tour != nil { TourBarView() }
                }
                .padding(24)
            }
            .frame(minWidth: 460)
            HostChatView()
                .frame(minWidth: 380)
                .padding(.vertical, 24)
                .padding(.trailing, 24)
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    /// Compact host HUD mirrored from the iPad/Mac capsule.
    private var hostStatus: some View {
        HStack(spacing: 12) {
            HostOrbGlyph(presence: model.hostPresence, color: model.theme.orbHalo.swiftUIColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.hostStateLabel).font(.caption.weight(.semibold))
                Text(model.hostAI.backend.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if model.dockedClusterID != nil {
                Button("Undock · 나와") { model.undockHost() }.controlSize(.small)
            }
            SpeakRepliesToggle(compact: false)
            Text(model.immersiveState == .open ? "In constellation" : "Window only")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var immersiveButton: some View {
        HStack {
            Button {
                Task { await toggleImmersive() }
            } label: {
                Label(model.immersiveState == .open ? "Leave Constellation · 나가기" : "Enter Constellation · 입장",
                      systemImage: model.immersiveState == .open ? "arrow.down.right.and.arrow.up.left" : "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.immersiveState == .inTransition)
            VoiceButton()
        }
    }

    private func toggleImmersive() async {
        switch model.immersiveState {
        case .open:
            model.immersiveState = .inTransition
            await dismissImmersiveSpace()
            model.immersiveState = .closed
        case .closed:
            model.immersiveState = .inTransition
            switch await openImmersiveSpace(id: "constellation") {
            case .opened: model.immersiveState = .open
            case .userCancelled, .error: model.immersiveState = .closed
            @unknown default: model.immersiveState = .closed
            }
        case .inTransition:
            break
        }
    }
}
#endif

// MARK: - iPad / Mac

#if !os(visionOS)
private struct SplitDashboard: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NavigatorView()
                .navigationTitle(model.graph.projectName)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } content: {
            ZStack(alignment: .bottom) {
                ConstellationViewport()
                    .ignoresSafeArea(edges: .bottom)
                VStack(spacing: 10) {
                    if model.tour != nil {
                        TourBarView()
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    HostHUDView()
                }
                .padding(16)
            }
            .overlay(alignment: .top) {
                if let toast = model.toast, !model.screenshotMode {
                    Text(toast)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.toast)
            // No title over the dark sky; the project name lives on the navigator column.
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .toolbar { toolbar }
#if os(iOS)
            .toolbarColorScheme(.dark, for: .navigationBar)
#endif
            .navigationSplitViewColumnWidth(min: 480, ideal: 800)
        } detail: {
            InspectorView(nodeID: nil)
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        }
    }

    private var themeSelection: Binding<String> {
        Binding(
            get: { model.theme.name },
            set: { name in
                if let preset = ConstellateTheme.presets.first(where: { $0.name == name }) { model.setTheme(preset) }
            }
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.showProjectImporter = true } label: { Label("Open Project", systemImage: "folder") }
                .help("Open a project folder (⌘O)")
            GranularityPicker(compact: true)
            Menu {
                Picker("Theme", selection: themeSelection) {
                    ForEach(ConstellateTheme.presets) { preset in
                        Text(preset.name).tag(preset.name)
                    }
                    if !ConstellateTheme.presets.contains(where: { $0.name == model.theme.name }) {
                        Text(model.theme.name).tag(model.theme.name)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Theme", systemImage: "paintpalette")
            }
            Button { Task { await model.startTour() } } label: { Label("Tour", systemImage: "figure.walk") }
            Button { model.addSimulatedMember() } label: {
                Label("Add member", systemImage: "person.badge.plus")
                    .overlay(alignment: .topTrailing) {
                        Text("\(model.participants.count)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(model.theme.orbHalo.swiftUIColor))
                            .offset(x: 10, y: -8)
                    }
            }
            .accessibilityLabel("Add simulated member")
            .accessibilityValue("\(model.participants.count) participants")
            .help("Add a simulated member (\(model.participants.count) in the meeting)")
            VoiceButton(compact: true)
        }
    }
}

/// Bottom capsule under the viewport: host state, last reply and the time dial.
struct HostHUDView: View {
    @Environment(AppModel.self) private var model
    @State private var question = ""
    @State private var isExpanded = false
    @State private var showTranscript = false
    @FocusState private var fieldFocused: Bool

    private var isThinking: Bool { model.hostAI.isThinking || model.hostActivity == .thinking }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                HostOrbGlyph(presence: model.hostPresence, color: model.theme.orbHalo.swiftUIColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.hostStateLabel).font(.caption.weight(.semibold))
                    if let last = model.hostTranscript.last(where: { $0.role == .host }) {
                        reply(last.text)
                    } else {
                        Text(model.hostAI.backend.label).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if model.dockedClusterID != nil {
                    Button("Undock · 나와") { model.undockHost() }
                }
                SpeakRepliesToggle(compact: true)
                Button { showTranscript = true } label: { Label("Transcript", systemImage: "text.bubble") }
                    .labelStyle(.iconOnly)
                    .help("Show the full host transcript")
                TimeDialView(compact: true).frame(width: 200)
            }
            HStack {
                TextField(model.screenshotMode ? "Ask the host…" : "Ask the host… (\"find views using @State\", \"explain\", \"tour\")", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit(submit)
                Button("Send", action: submit)
                    .disabled(isThinking || question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .sheet(isPresented: $showTranscript) {
            NavigationStack {
                HostChatView()
                    .padding()
                    .navigationTitle("Host transcript")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showTranscript = false } }
                    }
            }
            .frame(minWidth: 420, minHeight: 520)
            .presentationDetents([.medium, .large])
        }
    }

    /// Two-line clamp by default; tap to expand into a scrollable block (max 160 pt).
    @ViewBuilder
    private func reply(_ text: String) -> some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            if isExpanded {
                ScrollView {
                    Text(text).font(.callout).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(maxHeight: 160)
            } else {
                Text(text).font(.callout).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Collapse" : "Show the full reply")
    }

    private func submit() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        question = ""
        fieldFocused = false
        Task { await model.handleVoice(text) }
    }
}
#endif

// MARK: - Speak replies

/// "Speak replies · 음성 읽기" toggle (persisted via AppModel → UserDefaults).
struct SpeakRepliesToggle: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        @Bindable var model = model
        let toggle = Toggle(isOn: $model.speakReplies) {
            Label("Speak replies · 음성 읽기", systemImage: model.speakReplies ? "speaker.wave.2.fill" : "speaker.slash")
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .help("Read the host's replies aloud")
        .accessibilityLabel("Speak replies")
        if compact {
            toggle.labelStyle(.iconOnly)
        } else {
            toggle.labelStyle(.titleAndIcon)
        }
    }
}

// MARK: - Granularity

struct GranularityPicker: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        let picker = Picker("Orbs · 뭉치", selection: Binding(get: { model.granularity }, set: { model.setGranularity($0) })) {
            ForEach(ClusterGranularity.allCases) { g in
                Text(g.rawValue.capitalized).tag(g)
            }
        }
        if compact {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }
}

/// Small animated glyph standing in for the orb inside 2-D UI.
struct HostOrbGlyph: View {
    var presence: OrbEntity.Presence
    var color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: presence == .idle ? 0.5 : 1.0 / 30, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let energy: Double = presence == .thinking ? 1 : presence == .speaking ? 0.75 : presence == .listening ? 0.5 : 0.2
            let pulse = 1 + sin(t * (2 + energy * 6)) * 0.08 * energy
            ZStack {
                Circle().fill(color.opacity(0.25)).scaleEffect(pulse * 1.35)
                Circle().stroke(color.opacity(0.8), lineWidth: 1.5)
                    .rotationEffect(.radians(t * (0.6 + energy * 2)))
                    .scaleEffect(x: 1, y: 0.45)
                Circle().stroke(color.opacity(0.6), lineWidth: 1.5)
                    .rotationEffect(.radians(-t * (0.9 + energy * 2) + 1))
                    .scaleEffect(x: 0.45, y: 1)
                Circle().fill(.white).scaleEffect(0.45 * pulse)
            }
        }
        .frame(width: 34, height: 34)
        .accessibilityLabel("Host orb, \(String(describing: presence))")
    }
}

#Preview("Dashboard") {
    DashboardView()
        .environment(AppModel())
}
