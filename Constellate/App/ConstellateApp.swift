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

        WindowGroup("Code Inspector", id: "inspector", for: NodeID.self) { $nodeID in
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
        WindowGroup("Dashboard", id: "dashboard") {
            DashboardView().environment(model)
        }
        .defaultSize(width: 1440, height: 900)
        .commands { ConstellateCommands(model: model) }
#elseif os(visionOS)
        WindowGroup("Dashboard", id: "dashboard") {
            DashboardView().environment(model)
        }
        .defaultSize(width: 980, height: 680)
#else
        WindowGroup("Dashboard", id: "dashboard") {
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
            Button("Open Project…") { model.showProjectImporter = true }
                .keyboardShortcut("o", modifiers: .command)
            Button("Load Sample Project") { model.loadSample() }
        }
        CommandMenu("Constellation") {
            Button("Toggle Voice") { model.toggleVoice() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Find Code") { model.searchFocusToken += 1 }
                .keyboardShortcut("f", modifiers: .command)
            Divider()
            Menu("Theme") {
                ForEach(ConstellateTheme.presets) { preset in
                    Button(preset.name) { model.setTheme(preset) }
                }
            }
            Button("Reset Time Dial") { model.setTimeDial(0) }
                .keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
            Menu("Layout") {
                ForEach(Array(LayoutStyle.allCases.enumerated()), id: \.element) { index, style in
                    Button(style.label) { model.setLayoutStyle(style) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .control])
                }
            }
            Button("Cycle Relations (Off → Focus → All)") { model.cycleRelationMode() }
                .keyboardShortcut("l", modifiers: .command)
            Button("Show All Relation Kinds") { model.showAllRelations() }
                .disabled(model.hiddenRelations.isEmpty)
            Divider()
            Toggle("Speak Replies", isOn: Binding(get: { model.speakReplies }, set: { model.speakReplies = $0 }))
            Toggle("Screenshot Mode", isOn: Binding(get: { model.screenshotMode }, set: { model.screenshotMode = $0 }))
            Divider()
            Button("Start Tour") { Task { await model.startTour() } }
            Button("Undock Host") { model.undockHost() }
                .disabled(model.dockedClusterID == nil)
        }
    }
}
#endif
