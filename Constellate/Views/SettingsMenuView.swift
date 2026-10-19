import ConstellateKit
import SwiftUI

/// 언어 선택: 한국어(기본) / English. "고급" 아래에 두어 영어 모드가 평소에는 눈에 띄지 않게 한다.
struct LanguagePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker(L("언어", "Language"), selection: Binding(get: { model.language }, set: { model.setLanguage($0) })) {
            ForEach(HostLanguage.allCases) { language in
                Text(language.nativeName).tag(language)
            }
        }
    }
}

/// What the language switch affects — shown under the picker.
private struct LanguageFootnote: View {
    var body: some View {
        Text(L("호스트 AI 답변 · 음성 인식 · 화면 문구에 적용됩니다.", "Applies to host replies, speech recognition and the interface."))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Toolbar gear menu (iPad / Mac): voice replies, screenshot mode, and the advanced section with the language.
struct SettingsMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Menu {
            Toggle(isOn: $model.speakReplies) {
                Label(L("답변 음성 읽기", "Speak replies"), systemImage: "speaker.wave.2")
            }
            Toggle(isOn: $model.screenshotMode) {
                Label(L("스크린샷 모드", "Screenshot mode"), systemImage: "camera.viewfinder")
            }
            Divider()
            Menu {
                LanguagePicker().pickerStyle(.inline)
                LanguageFootnote()
            } label: {
                Label(L("고급", "Advanced"), systemImage: "gearshape.2")
            }
        } label: {
            Label(L("설정", "Settings"), systemImage: "gearshape")
        }
        .help(L("설정 · 영어 모드는 고급에 있습니다", "Settings · English mode is under Advanced"))
    }
}

/// visionOS panel section; the language picker is folded away under "고급".
struct SettingsPanel: View {
    @Environment(AppModel.self) private var model
    @State private var showAdvanced = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            Label(L("설정", "Settings"), systemImage: "gearshape").font(.headline)
            Toggle(L("답변 음성 읽기", "Speak replies"), isOn: $model.speakReplies)
            Toggle(L("스크린샷 모드", "Screenshot mode"), isOn: $model.screenshotMode)
            DisclosureGroup(L("고급", "Advanced"), isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 6) {
                    LanguagePicker().pickerStyle(.segmented)
                    LanguageFootnote()
                }
                .padding(.top, 6)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
