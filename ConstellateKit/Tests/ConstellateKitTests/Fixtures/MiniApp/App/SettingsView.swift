import SwiftUI

struct SettingsView: View {
    @Binding var showsCompleted: Bool

    var body: some View {
        Form {
            Toggle("Show completed", isOn: $showsCompleted)
        }
    }
}
