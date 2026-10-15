import SwiftUI

struct KeepAwakeView: View {
    @ObservedObject var controller: KeepAwakeController
    @State private var minutes = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Keep Displays Awake", systemImage: "sun.max")
                .font(PanelStyle.heading)
            if controller.isActive {
                HStack {
                    Text(controller.remainingLabel).monospacedDigit()
                        .accessibilityLabel("Keep Displays Awake, \(controller.remainingLabel)")
                    Spacer(minLength: 4)
                    Button("Stop") { controller.stop() }
                        .accessibilityLabel("Stop keeping displays awake")
                }
            } else {
                HStack {
                    Picker("Duration", selection: $minutes) {
                        ForEach(KeepAwakeController.durations, id: \.self) { duration in
                            Text("\(duration) minutes").tag(duration)
                        }
                    }.labelsHidden().fixedSize()
                        .accessibilityLabel("Keep Displays Awake duration")
                    Spacer(minLength: 4)
                    Button("Start") { controller.start(minutes: minutes) }
                        .accessibilityLabel("Start keeping displays awake")
                }
            }
            Text("Prevents idle display sleep. It does not override closing the lid, manual sleep or disconnected screens.")
                .foregroundStyle(.secondary)
            if let error = controller.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .font(PanelStyle.label).controlSize(.small)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: PanelStyle.radius))
    }
}
