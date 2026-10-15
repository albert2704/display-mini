import SwiftUI
import DisplayCore

struct PresetAutomationView: View {
    @ObservedObject var controller: PresetAutomationController
    let presets: [DisplayPreset]
    @State private var editor: ScheduleEditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Preset schedules", systemImage: "calendar.badge.clock").font(PanelStyle.heading)
                Spacer(minLength: 4)
                Button { editor = ScheduleEditorRequest(schedule: nil) } label: { Image(systemName: "plus") }
                    .controlSize(.small).accessibilityLabel("Add preset schedule")
                    .help("Add preset schedule")
                    .disabled(controller.storageError != nil || presets.isEmpty || controller.library.schedules.count >= 12)
            }
            Text("Runs at local time while Display Mini is open and your Mac is awake. Missed times are skipped.")
                .foregroundStyle(.secondary)
            if let error = controller.storageError {
                Text(error).foregroundStyle(.orange)
                Button("Back Up and Reset Schedules") { controller.resetUnreadableStorage() }.controlSize(.small)
            } else if controller.library.schedules.isEmpty {
                Text(presets.isEmpty ? "Save a preset in Presets to add your first schedule." : "Add a schedule for a saved preset. New schedules start off.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.library.schedules) { schedule in
                    Divider()
                    scheduleRow(schedule)
                }
                if controller.library.schedules.count >= 12 {
                    Text("12 schedules saved. Delete one to add another.").foregroundStyle(.secondary)
                }
            }
            if let message = controller.message { Text(message).foregroundStyle(.secondary) }
        }
        .font(PanelStyle.label).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: PanelStyle.radius))
        .sheet(item: $editor) { request in
            PresetScheduleEditor(controller: controller, presets: presets, schedule: request.schedule)
        }
    }

    private func scheduleRow(_ schedule: PresetSchedule) -> some View {
        let preset = presets.first { $0.id == schedule.presetID }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Toggle(isOn: Binding(get: { schedule.enabled }, set: { _ = controller.setEnabled(schedule.id, enabled: $0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset?.name ?? "Missing preset").font(PanelStyle.label.weight(.semibold)).lineLimit(1)
                        Text("\(schedule.timeTitle) · \(schedule.recurrence.title)").foregroundStyle(.secondary)
                    }
                }.toggleStyle(.switch).controlSize(.mini)
                    .accessibilityLabel("Schedule \(preset?.name ?? "missing preset") at \(schedule.timeTitle), \(schedule.recurrence.title)")
                Button { editor = ScheduleEditorRequest(schedule: schedule) } label: { Image(systemName: "pencil") }
                    .accessibilityLabel("Edit schedule at \(schedule.timeTitle)").help("Edit schedule")
                Button { controller.delete(schedule.id) } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Delete schedule at \(schedule.timeTitle)").help("Delete schedule")
            }.buttonStyle(.borderless)
            if preset == nil { Text("Choose another preset or delete this schedule.").foregroundStyle(.orange) }
            if let status = controller.statuses[schedule.id] { Text(status).foregroundStyle(.secondary) }
        }
    }
}

private struct ScheduleEditorRequest: Identifiable {
    let id = UUID()
    let schedule: PresetSchedule?
}

private struct PresetScheduleEditor: View {
    @ObservedObject var controller: PresetAutomationController
    let presets: [DisplayPreset]
    let schedule: PresetSchedule?
    @Environment(\.dismiss) private var dismiss
    @State private var presetID: UUID?
    @State private var time: Date
    @State private var recurrence: PresetScheduleRecurrence
    @State private var error: String?

    init(controller: PresetAutomationController, presets: [DisplayPreset], schedule: PresetSchedule?) {
        self.controller = controller; self.presets = presets; self.schedule = schedule
        _presetID = State(initialValue: schedule?.presetID ?? presets.first?.id)
        // A fixed ordinary day avoids today's DST gap altering the editable hour.
        let components = DateComponents(year: 2024, month: 1, day: 15, hour: schedule?.hour ?? 18, minute: schedule?.minute ?? 0)
        _time = State(initialValue: Calendar.current.date(from: components) ?? Date())
        _recurrence = State(initialValue: schedule?.recurrence ?? .daily)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(schedule == nil ? "Add preset schedule" : "Edit preset schedule").font(PanelStyle.heading)
            Picker("Preset", selection: $presetID) {
                if let selected = presetID, !presets.contains(where: { $0.id == selected }) {
                    Text("Missing preset").tag(Optional(selected))
                }
                ForEach(presets) { Text($0.name).tag(Optional($0.id)) }
            }.controlSize(.small)
            DatePicker("Local time", selection: $time, displayedComponents: .hourAndMinute).controlSize(.small)
            Picker("Repeat", selection: $recurrence) {
                ForEach(PresetScheduleRecurrence.allCases) { Text($0.title).tag($0) }
            }.controlSize(.small)
            Text(schedule == nil ? "Save, then turn on the schedule when you are ready." : "A schedule already handled today will run again on its next eligible day.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(presetID == nil || !presets.contains { $0.id == presetID })
            }
        }.font(PanelStyle.label).padding(18).frame(width: 290)
    }

    private func save() {
        guard let presetID else { return }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        if controller.save(id: schedule?.id, presetID: presetID, hour: parts.hour ?? 0,
                           minute: parts.minute ?? 0, recurrence: recurrence) { dismiss() }
        else { error = controller.message ?? controller.storageError ?? "The schedule could not be saved." }
    }
}
