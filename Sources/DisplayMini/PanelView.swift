import AppKit
import SwiftUI
import DisplayCore

enum PanelStyle {
    static let width: CGFloat = 300
    static let gap: CGFloat = 10
    static let radius: CGFloat = 14
    static let accent = Color(nsColor: .systemBlue)
    static let label = Font.system(size: 11)
    static let heading = Font.system(size: 13, weight: .semibold)
}

struct PanelView: View {
    @ObservedObject var store: DisplayStore
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: PanelStyle.gap) {
                    if store.displays.isEmpty {
                        VStack(spacing: PanelStyle.gap) {
                            Image(systemName: "display.trianglebadge.exclamationmark").font(.title)
                            Text("No displays available").font(PanelStyle.heading)
                            Text("Connect a display, then refresh.").font(PanelStyle.label).foregroundStyle(.secondary)
                            Button("Refresh Displays") { store.refresh() }
                        }.padding(24)
                    }
                    ForEach(store.displays) { device in DisplayCard(device: device, store: store) }
                }.padding(8)
            }.scrollIndicators(.hidden)
            if let name = store.pendingResolutionName {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keep this resolution?").font(PanelStyle.heading)
                    Text("\(name) · Reverting in \(store.secondsRemaining)s").font(PanelStyle.label).foregroundStyle(.secondary)
                    HStack {
                        Button("Revert") { store.revertResolution() }.keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("Keep") { store.keepResolution() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    }
                }.padding(12).background(PanelStyle.accent.opacity(0.1))
            }
            if let message = store.message {
                HStack(alignment: .top) {
                    Text(message).font(PanelStyle.label).fixedSize(horizontal: false, vertical: true)
                    Button { store.message = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss message")
                }.padding(10).background(Color.orange.opacity(0.12))
            }
            if store.unresolvedRecovery && store.pendingResolutionName == nil {
                Button("Keep current resolution") { store.keepCurrentResolution() }
                    .font(PanelStyle.label).padding(.bottom, 8)
            }
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                Text("Display Mini").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button { store.restoreDisplays() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Restore displays · ⌃⌥⌘R").accessibilityLabel("Restore Displays")
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh displays").accessibilityLabel("Refresh Displays")
                Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit Display Mini").accessibilityLabel("Quit Display Mini")
            }.font(.system(size: 12)).buttonStyle(.plain).padding(.horizontal, 14).padding(.vertical, 11)
        }
        .frame(width: PanelStyle.width)
        .frame(height: panelHeight)
        .background(.ultraThinMaterial)
        .tint(PanelStyle.accent)
    }
    private var panelHeight: CGFloat {
        let cards = store.displays.reduce(CGFloat(0)) { $0 + ($1.connected ? ($1.builtIn ? 139 : 211) : 78) + ($1.error == nil ? 0 : 50) }
        return min(730, max(180, cards + CGFloat(max(0, store.displays.count - 1)) * PanelStyle.gap + 52)
                   + (store.pendingResolutionName == nil ? 0 : 108) + (store.message == nil ? 0 : 65))
    }
}

private struct DisplayCard: View {
    @ObservedObject var device: DisplayDevice
    @ObservedObject var store: DisplayStore
    @State private var showDDC = false
    private var busy: Bool { store.connectionBusy || store.pendingResolutionName != nil }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: device.builtIn ? "laptopcomputer" : "display").font(.system(size: 13))
                    .accessibilityHidden(true)
                Text(device.name).font(PanelStyle.heading).lineLimit(1).help(device.name)
                Spacer(minLength: 2)
                Toggle("Connect \(device.name)", isOn: Binding(get: { device.connected }, set: { store.toggleConnection(device, enabled: $0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .disabled(!store.native.canConnect || !ControlMath.mayDisconnect(isEnabled: device.connected, activeCount: store.activeCount, pending: busy))
                    .help(device.connected && store.activeCount <= 1 ? "The last connected display must stay on" : "Disconnect or reconnect this display")
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: PanelStyle.radius))
            if device.connected {
                VStack(spacing: 9) {
                    if !device.builtIn {
                        Button { showDDC.toggle() } label: {
                            HStack(spacing: 5) {
                                if device.reading { ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 12, height: 12) }
                                else { Image(systemName: "display.2") }
                                Text(device.reading ? "Detecting monitor controls…" : (!device.ddcBrightness && !device.nativeBrightness ? "Configure DDC…" : "Monitor Controls…"))
                                    .font(.system(size: 11, weight: .semibold))
                            }.frame(maxWidth: .infinity).padding(.vertical, 5)
                        }
                        .buttonStyle(.plain).foregroundStyle(.white)
                        .background(PanelStyle.accent.gradient, in: Capsule())
                        .popover(isPresented: $showDDC, arrowEdge: .trailing) { DDCSettings(device: device, store: store) }
                    }
                    SliderRow(label: "Brightness (\(device.brightnessMethod))", valueText: "\(Int((device.brightness * 100).rounded()))%", icon: "sun.max.fill") {
                        CompactSlider(value: Binding(get: { device.brightness }, set: { store.setBrightness(device, $0) }), accessibilityName: "\(device.name) brightness")
                            .frame(height: 22)
                            .disabled(busy || (device.reading && !device.nativeBrightness))
                    }
                    if !device.builtIn {
                        SliderRow(label: "Volume", valueText: device.volume.map { "\(Int(($0 * 100).rounded()))%" } ?? (device.reading ? "Reading…" : "Unavailable"), icon: "speaker.wave.2.fill") {
                            CompactSlider(value: Binding(get: { device.volume ?? 0 }, set: { store.setVolume(device, $0) }), accessibilityName: "\(device.name) volume")
                                .frame(height: 22)
                                .disabled(device.volume == nil || device.reading || busy)
                        }
                    }
                    VStack(spacing: 0) {
                        HStack {
                            Text("Resolution").font(PanelStyle.label).foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                ForEach(device.modes) { mode in
                                    Button {
                                        store.changeResolution(device, mode: mode)
                                    } label: {
                                        if mode.id == device.currentModeID { Label("\(mode.size) · \(mode.detail)", systemImage: "checkmark") }
                                        else { Text("\(mode.size) · \(mode.detail)") }
                                    }
                                }
                            } label: { Text(previewSize).font(PanelStyle.label).monospacedDigit() }
                            .menuStyle(.borderlessButton).fixedSize().disabled(busy || device.modes.isEmpty)
                            .accessibilityLabel("\(device.name) resolution")
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right.square").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 15).accessibilityHidden(true)
                            CompactSlider(value: $device.modeIndex, range: 0...Double(max(1, device.sliderModes.count - 1)), accessibilityName: "\(device.name) resolution scale", onCommit: { store.commitSliderResolution(device) })
                                .frame(height: 22).disabled(device.sliderModes.count < 2 || busy)
                        }
                    }
                    if let error = device.error {
                        Text(error).font(PanelStyle.label).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                    Text("Disconnected").font(PanelStyle.label)
                    Spacer()
                }.foregroundStyle(.secondary).padding(12)
                if let error = device.error { Text(error).font(PanelStyle.label).foregroundStyle(.orange).padding(10) }
            }
        }
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: PanelStyle.radius))
    }

    private var previewSize: String {
        guard !device.sliderModes.isEmpty else { return device.currentMode?.size ?? "Unavailable" }
        let index = min(device.sliderModes.count - 1, max(0, Int(device.modeIndex.rounded())))
        return device.sliderModes[index].size
    }
}

private struct SliderRow<Control: View>: View {
    let label: String
    let valueText: String
    let icon: String
    @ViewBuilder var control: () -> Control
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                Spacer()
                Text(valueText).monospacedDigit()
            }.font(PanelStyle.label).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 15).accessibilityHidden(true)
                control().tint(.primary)
            }
        }
    }
}

private struct DDCSettings: View {
    @ObservedObject var device: DisplayDevice
    @ObservedObject var store: DisplayStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(device.name, systemImage: "display").font(PanelStyle.heading)
            Text("Monitor controls").font(.system(size: 20, weight: .semibold))
            Text("DDC/CI lets this app adjust your monitor’s own brightness and speakers.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack { Text("Brightness"); Spacer(); Text(device.ddcBrightness ? "Supported" : "Software dimming").foregroundStyle(.secondary) }
            HStack { Text("Volume"); Spacer(); Text(device.volume != nil ? "Supported" : "Unavailable").foregroundStyle(.secondary) }
            Divider()
            Toggle("Use software brightness only", isOn: Binding(get: { device.forceSoftware }, set: { store.setSoftwareOnly(device, $0) }))
                .disabled(device.reading || device.writing)
            if let detail = device.ddcDetail {
                Text(detail).font(PanelStyle.label).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("If controls are unavailable, enable DDC/CI in the monitor’s menu. Some docks and adapters block these commands. Try a direct USB-C, DisplayPort, or HDMI connection.")
                .font(PanelStyle.label).foregroundStyle(.secondary)
            Button(device.reading ? "Checking…" : "Detect Again") { store.retryDDC(device) }
                .buttonStyle(.borderedProminent).disabled(device.reading || device.writing)
        }.font(.system(size: 12)).padding(18).frame(width: 290)
    }
}
