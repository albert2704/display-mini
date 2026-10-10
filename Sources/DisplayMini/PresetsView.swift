import SwiftUI
import DisplayCore

struct PresetsView: View {
    @ObservedObject var store: DisplayStore
    @State private var name = ""
    @State private var editing: UUID?
    @State private var editedName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Display presets", systemImage: "slider.horizontal.3").font(PanelStyle.heading)
            Text("Save brightness and monitor volume for your connected screens.")
                .font(PanelStyle.label).foregroundStyle(.secondary)
            if let error = store.presetStorageError {
                Text(error).font(PanelStyle.label).foregroundStyle(.orange)
                Button("Back Up and Reset Presets") { store.resetUnreadablePresets() }
            } else {
                HStack {
                    TextField("Preset name", text: $name).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("New preset name")
                        .onSubmit(save)
                    Button("Save Current", action: save).buttonStyle(.borderedProminent)
                        .disabled(!store.canSavePreset || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !store.canSavePreset && store.applyingPresetName == nil {
                    Text("Connect a screen and wait for its controls to finish before saving or applying.")
                        .font(PanelStyle.label).foregroundStyle(.secondary)
                }
                Divider()
                ScrollView {
                    if store.presetLibrary.presets.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "sun.max").font(.title2).foregroundStyle(PanelStyle.accent)
                            Text("Your first preset").font(PanelStyle.heading)
                            Text("Adjust your displays, then save a name like Work or Evening.")
                                .font(PanelStyle.label).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(store.presetLibrary.presets.enumerated()), id: \.element.id) { index, preset in
                                presetRow(preset, index: index)
                            }
                        }
                    }
                }
            }
            if let applying = store.applyingPresetName {
                HStack { ProgressView().controlSize(.small); Text("Applying “\(applying)”…") }
                    .font(PanelStyle.label)
            }
            if let message = store.presetMessage {
                Text(message).font(PanelStyle.label).fixedSize(horizontal: false, vertical: true)
            }
            Text("Missing screens are skipped. Resolution and connection stay as they are.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.font(.system(size: 12)).padding(18).frame(width: 380, height: 440)
    }

    private func save() {
        if store.savePreset(name: name) { name = "" }
    }

    @ViewBuilder private func presetRow(_ preset: DisplayPreset, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if editing == preset.id {
                TextField("Preset name", text: $editedName).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Rename \(preset.name)")
                HStack {
                    Button("Cancel") { editing = nil }
                    Spacer()
                    Button("Save Name") {
                        if store.renamePreset(preset.id, name: editedName) { editing = nil }
                    }.buttonStyle(.borderedProminent)
                }.disabled(store.applyingPresetName != nil)
            } else {
                HStack {
                    Text(preset.name).font(PanelStyle.heading).lineLimit(1).help(preset.name)
                    Spacer()
                    if index < 3 { Text("⌃⌥⌘\(index + 1)").font(.system(size: 10)).foregroundStyle(.secondary) }
                }
                ForEach(preset.displays, id: \.uuid) { display in
                    Text("\(display.name) · ☀ \(Int((display.brightness * 100).rounded()))%" +
                         (display.volume.map { " · Volume \(Int(($0 * 100).rounded()))%" } ?? ""))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack {
                    Button("Apply") { store.applyPreset(preset) }.disabled(!store.canSavePreset)
                        .accessibilityLabel("Apply \(preset.name)")
                    Spacer()
                    Button { editedName = preset.name; editing = preset.id } label: { Image(systemName: "pencil") }
                        .accessibilityLabel("Rename \(preset.name)").help("Rename preset")
                    Button { store.deletePreset(preset.id) } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete \(preset.name)").help("Delete preset")
                }.disabled(store.applyingPresetName != nil)
            }
        }.padding(11).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
}
