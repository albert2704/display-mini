import SwiftUI
import DisplayCore

struct DisplaySettingsView: View {
    @ObservedObject var device: DisplayDevice
    @ObservedObject var store: DisplayStore
    @State private var name = ""
    private var settings: DisplayPersonalization.Entry { store.personalization.entry(for: device.id) }
    private var available: [FavoriteResolution] {
        guard device.connected else { return [] }
        var seen = Set<FavoriteResolution>()
        return device.modes.compactMap(\.favorite).filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Display settings", systemImage: "display").font(PanelStyle.heading)
            Text(device.systemName).font(PanelStyle.label).foregroundStyle(.secondary)
                .lineLimit(2).help(device.systemName)
            if let error = store.personalizationStorageError {
                Text(error).font(PanelStyle.label).foregroundStyle(.orange)
                Button("Back Up and Reset Display Settings") { store.resetUnreadablePersonalization(); name = "" }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display name").font(PanelStyle.heading)
                    TextField(device.systemName, text: $name).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Custom display name").onSubmit(saveName)
                    HStack {
                        Button("Use System Name") { if store.renameDisplay(device, name: "") { name = "" } }
                            .disabled(settings.name == nil)
                        Spacer()
                        Button("Save Name", action: saveName).buttonStyle(.borderedProminent)
                            .disabled(name == (settings.name ?? ""))
                    }
                }
                Divider()
                HStack {
                    Text("Favorite resolutions").font(PanelStyle.heading)
                    Spacer()
                    Text("\(settings.favorites.count)/32").font(PanelStyle.label).foregroundStyle(.secondary)
                }
                if device.connected, let current = device.currentMode?.favorite {
                    Button {
                        store.setFavorite(device, mode: current, enabled: !settings.favorites.contains(current))
                    } label: {
                        Label(settings.favorites.contains(current) ? "Unstar Current Resolution" : "Star Current Resolution",
                              systemImage: settings.favorites.contains(current) ? "star.fill" : "star")
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if settings.favorites.isEmpty {
                            Text("Star the resolutions you use most. They appear at the top of this screen’s resolution menu.")
                                .font(PanelStyle.label).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(PanelStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        } else {
                            VStack(spacing: 10) {
                                ForEach(settings.favorites) { mode in
                                    resolutionRow(mode, saved: true, unavailable: !available.contains(mode))
                                }
                            }.padding(12).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                        }
                        Text("Available resolutions").font(PanelStyle.heading)
                        if available.isEmpty {
                            Text(device.connected ? "No resolutions are available. Refresh the display and try again." : "Reconnect this screen to see its available resolutions.")
                                .font(PanelStyle.label).foregroundStyle(.secondary)
                        } else {
                            ForEach(available) { mode in
                                resolutionRow(mode, saved: settings.favorites.contains(mode), unavailable: false)
                            }
                        }
                    }.padding(.trailing, 4)
                }
                Text("Starring saves a shortcut, without changing resolution. Selecting a favorite still asks you to Keep or Revert.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let message = store.personalizationMessage {
                Text(message).font(PanelStyle.label).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.font(.system(size: 12)).padding(18).frame(width: 360, height: 560)
            .tint(PanelStyle.accent)
            .onAppear { name = settings.name ?? ""; store.personalizationMessage = nil }
    }

    private func saveName() {
        if store.renameDisplay(device, name: name) { name = settings.name ?? "" }
    }

    private func resolutionRow(_ mode: FavoriteResolution, saved: Bool, unavailable: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(mode.title).monospacedDigit()
                Text(mode.detail + (unavailable ? " · Unavailable" : ""))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.setFavorite(device, mode: mode, enabled: !saved) } label: {
                Image(systemName: saved ? "star.fill" : "star")
                    .foregroundStyle(saved ? PanelStyle.accent : .secondary)
            }.buttonStyle(.borderless)
                .help(saved ? "Remove favorite" : "Add favorite")
                .accessibilityLabel("\(saved ? "Remove" : "Add") favorite \(mode.title), \(mode.detail)")
                .accessibilityValue(saved ? "Starred" : "Not starred")
        }
    }
}
