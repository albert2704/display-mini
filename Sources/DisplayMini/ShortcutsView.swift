import SwiftUI

struct ShortcutsView: View {
    @ObservedObject var store: DisplayStore
    @ObservedObject private var recorder: ShortcutRecorder
    @State private var editing: DisplayShortcut?
    @State private var draft = DisplayShortcut.brightnessUp.defaultBinding

    init(store: DisplayStore) {
        self.store = store; self.recorder = store.shortcutRecorder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Keyboard shortcuts", systemImage: "keyboard").font(PanelStyle.heading)
            if let action = editing {
                editor(action)
            } else {
                Toggle("Enable everyday shortcuts", isOn: $store.shortcutsEnabled)
                    .toggleStyle(.switch).controlSize(.small)
                Text("Point at a screen to adjust brightness or monitor volume by 5%. Click a key combination to change it.")
                    .font(PanelStyle.label).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(spacing: 8) {
                            ForEach(DisplayShortcut.allCases, id: \.rawValue) { action in
                                HStack {
                                    Text(action.title)
                                    Spacer()
                                    Button(store.shortcutKeys(action)) {
                                        draft = store.shortcutPreferences[action]
                                        store.shortcutEditMessage = nil; editing = action
                                    }.monospaced().frame(minWidth: 84, alignment: .trailing)
                                        .accessibilityLabel("Change \(action.title) shortcut")
                                        .help("Change \(action.title): \(store.shortcutKeys(action))")
                                }
                            }
                        }.padding(12).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                        Text("Preset keys follow the saved list order. Volume and mute require monitor DDC support.")
                            .font(PanelStyle.label).foregroundStyle(.secondary)
                        Text("Restore stays enabled when everyday shortcuts are off. ⌃⌥⌘R is always reserved as a recovery fallback.")
                            .font(PanelStyle.label).foregroundStyle(.secondary)
                        if let message = store.shortcutStorageMessage {
                            Text(message).font(PanelStyle.label).foregroundStyle(.orange)
                        }
                        ForEach(store.shortcutErrors, id: \.self) { error in
                            Label(error, systemImage: "exclamationmark.triangle").font(PanelStyle.label).foregroundStyle(.orange)
                        }
                    }
                }
                Button("Reset All to Defaults") { store.resetShortcuts() }
                if let error = store.shortcutEditMessage { Text(error).font(PanelStyle.label).foregroundStyle(.orange) }
            }
        }.font(.system(size: 12)).padding(18).frame(width: 380, height: 520)
            .onDisappear { recorder.endEditing(); store.shortcutEditMessage = nil }
    }

    private func editor(_ action: DisplayShortcut) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(action.title).font(.system(size: 15, weight: .semibold))
            Text(recorder.isRecording ? (recorder.heldModifiers.isEmpty ? "Press shortcut…" : recorder.heldModifiers + "…") : draft.label)
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(PanelStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(recorder.isRecording ? "Listening for a shortcut" : "New shortcut: \(draft.label)")
            Button(recorder.isRecording ? "Stop Recording" : "Record Shortcut") {
                if recorder.isRecording { recorder.cancel() }
                else {
                    store.shortcutEditMessage = nil
                    recorder.start { binding in draft = binding }
                }
            }.frame(maxWidth: .infinity)
            if recorder.isRecording {
                Text("Press a combination with Control or Command. Escape cancels.")
                    .font(PanelStyle.label).foregroundStyle(.secondary)
            } else if let message = recorder.message {
                Text(message).font(PanelStyle.label).foregroundStyle(.secondary)
            }
            if recorder.isRecording, let message = recorder.message {
                Text(message).font(PanelStyle.label).foregroundStyle(.orange)
            }
            HStack {
                Text("Key")
                Spacer()
                Menu {
                    ForEach(ShortcutKey.groups) { group in
                        Menu(group.title) {
                            ForEach(group.keys) { key in
                                Button {
                                    recorder.stop()
                                    draft.keyCode = key.id; store.shortcutEditMessage = nil
                                } label: {
                                    if draft.keyCode == key.id { Label(key.label, systemImage: "checkmark") }
                                    else { Text(key.label) }
                                }
                            }
                        }
                    }
                } label: {
                    Text(ShortcutKey.choices.first { $0.id == draft.keyCode }?.label ?? "Choose")
                }.menuStyle(.borderedButton).frame(width: 120).accessibilityLabel("Shortcut key")
            }.disabled(recorder.isRecording)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                GridRow {
                    modifier("Control", symbol: "⌃", flag: .control)
                    modifier("Option", symbol: "⌥", flag: .option)
                }
                GridRow {
                    modifier("Shift", symbol: "⇧", flag: .shift)
                    modifier("Command", symbol: "⌘", flag: .command)
                }
            }.disabled(recorder.isRecording)
            Text("Include Control or Command. Key labels use US keyboard positions; function keys may also need Fn on your keyboard.")
                .font(PanelStyle.label).foregroundStyle(.secondary)
            if !store.shortcutsEnabled && action != .restore {
                Text("Saved now; active when everyday shortcuts are enabled.").font(PanelStyle.label).foregroundStyle(.secondary)
            }
            if let error = store.shortcutEditMessage {
                Text(error).font(PanelStyle.label).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                Button("Default") { recorder.stop(); draft = action.defaultBinding; store.shortcutEditMessage = nil }
                Spacer()
                Button("Cancel") { recorder.endEditing(); editing = nil; store.shortcutEditMessage = nil }
                Button("Save") {
                    if store.saveShortcut(action, binding: draft) { recorder.endEditing(); editing = nil }
                }.buttonStyle(.borderedProminent).disabled(!draft.isValid || recorder.isRecording)
            }
        }.onAppear { recorder.beginEditing() }.onDisappear { recorder.endEditing() }
    }

    private func modifier(_ title: String, symbol: String, flag: ShortcutModifiers) -> some View {
        Toggle("\(symbol) \(title)", isOn: Binding(get: { draft.modifiers.contains(flag) }, set: { enabled in
            recorder.stop()
            if enabled { draft.modifiers.insert(flag) } else { draft.modifiers.remove(flag) }
            store.shortcutEditMessage = nil
        })).toggleStyle(.checkbox).accessibilityLabel("\(title) modifier")
    }
}
