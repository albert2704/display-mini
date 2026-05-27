import SwiftUI
import DisplayCore

struct AdvancedView: View {
    @ObservedObject var store: DisplayStore
    var body: some View {
        VStack(spacing: PanelStyle.gap) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $store.linkedBrightnessEnabled) {
                    Label("Link brightness", systemImage: "link").font(PanelStyle.heading)
                }.toggleStyle(.switch).controlSize(.small)
                Text("Brightness changes in Display Mini apply the same percentage to all ready screens. Presets keep their individual levels.")
                    .font(PanelStyle.label).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(12).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: PanelStyle.radius))
            ForEach(store.displays) { device in AdvancedDisplayCard(device: device, store: store) }
        }
    }
}

struct AdvancedDisplayCard: View {
    @ObservedObject var device: DisplayDevice
    @ObservedObject var store: DisplayStore
    @State private var contrastDraft: Double?
    @State private var selectedInput = MonitorInput.hdmi1
    @State private var confirmingInput = false
    private var ready: Bool { store.canConfigureDDC(device) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(device.name, systemImage: device.builtIn ? "laptopcomputer" : "display")
                .font(PanelStyle.heading).lineLimit(1).help(device.name)
            if device.connected {
                refreshRate
                Divider()
                if device.builtIn {
                    Text("Contrast and input switching are controls on external monitors.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("Monitor hardware").font(PanelStyle.heading)
                        Spacer()
                        if device.advancedBusy { ProgressView().controlSize(.small) }
                        Button(device.advancedProbe == nil ? "Detect" : "Check Again") { store.detectAdvancedControls(device) }
                            .controlSize(.small).disabled(!ready)
                            .accessibilityLabel("Detect advanced controls for \(device.name)")
                    }
                    if let probe = device.advancedProbe {
                        contrastControl(probe)
                        inputControl(probe)
                    } else if !device.advancedBusy && device.advancedMessage == nil {
                        Text("Detect contrast and input support for this connection. This reads the monitor without changing its settings.")
                            .foregroundStyle(.secondary)
                    }
                    if let message = device.advancedMessage {
                        Text(message).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            } else {
                Label("Reconnect this screen to use advanced controls.", systemImage: "power").foregroundStyle(.secondary)
            }
        }
        .font(PanelStyle.label).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: PanelStyle.radius))
        .onAppear {
            if let value = device.advancedProbe?.currentInput, let input = MonitorInput(rawValue: value) { selectedInput = input }
        }
        .onChange(of: device.advancedProbe?.currentInput) { _, value in
            if let value, let input = MonitorInput(rawValue: value) { selectedInput = input }
        }
        .onChange(of: device.advancedRevision) { _, _ in contrastDraft = nil }
        .alert("Switch \(device.name) to \(selectedInput.title)?", isPresented: $confirmingInput) {
            Button("Cancel", role: .cancel) {}
            Button("Switch Input") { store.switchInput(device, to: selectedInput) }
        } message: {
            Text("The Mac’s picture may disappear from this monitor. Use the monitor’s own buttons to switch back. These are common input codes; your monitor may use different ones.")
        }
    }

    private var refreshRate: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Refresh rate", systemImage: "arrow.triangle.2.circlepath")
                Spacer(minLength: 4)
                Menu {
                    ForEach(store.refreshRateModes(device)) { mode in
                        Button { store.changeRefreshRate(device, to: mode) } label: {
                            if mode == device.currentMode?.favorite { Label(mode.refreshTitle, systemImage: "checkmark") }
                            else { Text(mode.refreshTitle) }
                        }
                    }
                } label: { Text(device.currentMode?.favorite?.refreshTitle ?? "Unavailable").monospacedDigit() }
                    .menuStyle(.borderlessButton).fixedSize()
                    .disabled(!ready || store.refreshRateModes(device).count < 2)
                    .accessibilityLabel("\(device.name) refresh rate")
            }
            Text("Keeps \(device.currentMode?.size ?? "the current resolution"). Changes revert after 15 seconds unless kept.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func contrastControl(_ probe: AdvancedDDCProbe) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Contrast", systemImage: "circle.lefthalf.filled")
                Spacer()
                Text(device.contrast.map { "\(Int(((contrastDraft ?? $0) * 100).rounded()))%" } ?? "Unavailable").monospacedDigit()
            }
            if device.contrast != nil {
                CompactSlider(value: Binding(get: { contrastDraft ?? device.contrast ?? 0 }, set: { contrastDraft = $0 }),
                              accessibilityName: "\(device.name) contrast", onCommit: {
                    if let value = contrastDraft { store.setContrast(device, value) }
                    contrastDraft = nil
                }).frame(height: 22).disabled(!ready)
            } else { Text(probe.contrast.status.title).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func inputControl(_ probe: AdvancedDDCProbe) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Input source", systemImage: "cable.connector")
            if let current = probe.currentInput {
                Text("Current: \(MonitorInput.title(for: current))").foregroundStyle(.secondary)
                HStack {
                    Picker("Input source", selection: $selectedInput) {
                        ForEach(MonitorInput.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().controlSize(.small).disabled(!ready)
                        .accessibilityLabel("\(device.name) input source")
                    Button("Switch…") { confirmingInput = true }
                        .controlSize(.small).disabled(!ready || current == selectedInput.rawValue || store.inputSwitchNeedsBuiltInRestore)
                }
                Text(store.inputSwitchNeedsBuiltInRestore ? "Use Restore Displays to reconnect the built-in screen before switching input." : "Common inputs, not detected ports. Use the monitor’s buttons to return to the Mac.")
                    .foregroundStyle(.secondary)
            } else { Text(probe.input.status.title).foregroundStyle(.secondary) }
            if probe.contrast.status != .ok || probe.input.status != .ok {
                Text("Check DDC/CI in the monitor menu. Try Slow timing in Monitor Controls or a direct cable connection.").foregroundStyle(.secondary)
            }
        }
    }
}
