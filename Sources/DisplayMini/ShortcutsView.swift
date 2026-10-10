import SwiftUI

struct ShortcutsView: View {
    @ObservedObject var store: DisplayStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Keyboard shortcuts", systemImage: "keyboard").font(PanelStyle.heading)
                Toggle("Enable everyday shortcuts", isOn: $store.shortcutsEnabled)
                    .toggleStyle(.switch).controlSize(.small)
                Text("Point at a screen to adjust its brightness or monitor volume. Each arrow press changes the level by 5%.")
                    .font(PanelStyle.label).foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    ForEach(DisplayShortcut.allCases.filter { $0 != .restore }, id: \.rawValue) { action in
                        HStack { Text(action.title); Spacer(); Text(action.keys).foregroundStyle(.secondary) }
                    }
                }.padding(12).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                Text("Preset keys follow the saved list order and apply to all matching screens. Volume and mute require monitor DDC support.")
                    .font(PanelStyle.label).foregroundStyle(.secondary)
                Divider()
                HStack { Text("Restore displays"); Spacer(); Text("⌃⌥⌘R").foregroundStyle(.secondary) }
                Text("The recovery shortcut stays enabled independently of everyday shortcuts. No keyboard-monitoring permission is required.")
                    .font(PanelStyle.label).foregroundStyle(.secondary)
                ForEach(store.shortcutErrors, id: \.self) { error in
                    Label(error, systemImage: "exclamationmark.triangle").font(PanelStyle.label).foregroundStyle(.orange)
                }
            }.font(.system(size: 12)).padding(18)
        }.frame(width: 340, height: 440)
    }
}
