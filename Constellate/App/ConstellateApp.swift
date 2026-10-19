import ConstellateKit
import SwiftUI

@main
struct ConstellateApp: App {
    @State private var model = AppModel()
#if os(visionOS)
    @State private var immersionStyle: ImmersionStyle = .progressive
#endif

    var body: some Scene {
        dashboard

        WindowGroup(L("코드 인스펙터", "Code Inspector"), id: "inspector", for: NodeID.self) { $nodeID in
            CodeInspectorWindow(nodeID: nodeID)
                .environment(model)
        }

#if os(visionOS)
        ImmersiveSpace(id: "constellation") {
            ConstellationImmersiveView()
                .environment(model)
        }
        .immersionStyle(selection: $immersionStyle, in: .progressive, .full)
        .upperLimbVisibility(.visible)
#endif
    }

    private var dashboard: some Scene {
#if os(macOS)
        WindowGroup(L("대시보드", "Dashboard"), id: "dashboard") {
            DashboardView().environment(model)
        }
        .defaultSize(width: 1440, height: 900)
        .commands { ConstellateCommands(model: model) }
#elseif os(visionOS)
        WindowGroup(L("대시보드", "Dashboard"), id: "dashboard") {
            DashboardView().environment(model)
        }
        .defaultSize(width: 980, height: 680)
#else
        WindowGroup(L("대시보드", "Dashboard"), id: "dashboard") {
            DashboardView().environment(model)
        }
#endif
    }
}

#if os(macOS)
struct ConstellateCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("프로젝트 열기…", "Open Project…")) { model.showProjectImporter = true }
                .keyboardShortcut("o", modifiers: .command)
            Button(L("샘플 프로젝트 불러오기", "Load Sample Project")) { model.loadSample() }
        }
        CommandMenu(L("별자리", "Constellation")) {
            Button(L("음성 켜기/끄기", "Toggle Voice")) { model.toggleVoice() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Button(L("코드 찾기", "Find Code")) { model.searchFocusToken += 1 }
                .keyboardShortcut("f", modifiers: .command)
            Divider()
            Menu(L("테마", "Theme")) {
                ForEach(ConstellateTheme.presets) { preset in
                    Button(themeDisplayName(preset.name)) { model.setTheme(preset) }
                }
            }
            Button(L("타임 다이얼 초기화", "Reset Time Dial")) { model.setTimeDial(0) }
                .keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
            Menu(L("배치", "Layout")) {
                ForEach(Array(LayoutStyle.allCases.enumerated()), id: \.element) { index, style in
                    Button(style.name(model.language)) { model.setLayoutStyle(style) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .control])
                }
            }
            Button(L("관계 표시 순환 (끔 → 선택 → 전체)", "Cycle Relations (Off → Focus → All)")) { model.cycleRelationMode() }
                .keyboardShortcut("l", modifiers: .command)
            Button(L("모든 관계 종류 표시", "Show All Relation Kinds")) { model.showAllRelations() }
                .disabled(model.hiddenRelations.isEmpty)
            Divider()
            Toggle(L("답변 음성 읽기", "Speak Replies"), isOn: Binding(get: { model.speakReplies }, set: { model.speakReplies = $0 }))
            Toggle(L("스크린샷 모드", "Screenshot Mode"), isOn: Binding(get: { model.screenshotMode }, set: { model.screenshotMode = $0 }))
            // English mode stays out of the way: a submenu under "고급".
            Menu(L("고급", "Advanced")) {
                Picker(L("언어", "Language"), selection: Binding(get: { model.language }, set: { model.setLanguage($0) })) {
                    ForEach(HostLanguage.allCases) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
            }
            Divider()
            Button(L("투어 시작", "Start Tour")) { Task { await model.startTour() } }
            Button(L("호스트 분리", "Undock Host")) { model.undockHost() }
                .disabled(model.dockedClusterID == nil)
        }
    }
}
#endif
