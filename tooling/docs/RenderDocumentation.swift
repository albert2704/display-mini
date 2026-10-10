import SwiftUI

enum DocumentationDefaults {
    static let domain = "dev.albert.DisplayMini.documentation.\(UUID().uuidString)"
    static let shared = UserDefaults(suiteName: domain)!
}

extension DisplayStore {
    func seedDocumentation() {
        let builtIn = DisplayDevice(id: "00000000-0000-4000-8000-000000000001", displayID: 0, name: "Built-in Display", builtIn: true)
        let external = DisplayDevice(id: "00000000-0000-4000-8000-000000000002", displayID: 0, name: "External Display", builtIn: false)
        builtIn.nativeBrightness = true; builtIn.brightnessMethod = "Combined"
        builtIn.brightness = 0.7; builtIn.confirmedBrightness = 0.7
        external.ddcBrightness = true; external.brightnessMethod = "Combined"
        external.brightness = 0.8; external.confirmedBrightness = 0.8
        external.volume = 0.5; external.confirmedVolume = 0.5
        for (display, width, height) in [(builtIn, 1728, 1117), (external, 2560, 1440)] {
            display.modes = [DisplayMode(id: 1, width: width * 3 / 4, height: height * 3 / 4),
                             DisplayMode(id: 2, width: width, height: height),
                             DisplayMode(id: 3, width: width * 5 / 4, height: height * 5 / 4)]
            display.sliderModes = display.modes; display.currentModeID = 2; display.modeIndex = 1
        }
        let report = """
        {"schema":1,"uuid":"00000000-0000-4000-8000-000000000002","transport":"standard","serviceCount":1,
        "delayMS":50,"brightness":{"status":"ok","current":75,"maximum":100,"attempts":1},
        "volume":{"status":"ok","current":50,"maximum":100,"attempts":1}}
        """
        external.ddcProbe = DDCProbe.parse(Data(report.utf8), expectedUUID: external.id, timing: .standard)
        precondition(external.ddcProbe != nil)
        displays = [builtIn, external]
        for (name, brightness, volume) in [("Work", 0.8, 0.5), ("Evening", 0.35, 0.2)] {
            let entries = [PresetDisplay(uuid: builtIn.id, name: builtIn.name, brightness: brightness, volume: nil),
                           PresetDisplay(uuid: external.id, name: external.name, brightness: brightness, volume: volume)]
            try! presetLibrary.save(name: name, displays: entries)
        }
    }
}

extension ShortcutsView {
    init(documenting store: DisplayStore, binding: ShortcutBinding) {
        self.init(store: store)
        _editing = State(initialValue: .brightnessUp)
        _draft = State(initialValue: binding)
    }
}

extension PanelView {
    init(documentingAdvanced store: DisplayStore) {
        self.init(store: store)
        _tab = State(initialValue: .advanced)
    }
}

extension ShortcutRecorder {
    func documentationState(listening: Bool = false, recorded: String? = nil) {
        isRecording = listening
        message = recorded.map { "Recorded \($0). Click Save to use it." }
    }
}

@main struct DocumentationRenderer {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        defer { DocumentationDefaults.shared.removePersistentDomain(forName: DocumentationDefaults.domain) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let store = DisplayStore(startMonitoring: false, shortcutDefaults: DocumentationDefaults.shared, personalizationDefaults: DocumentationDefaults.shared, advancedDefaults: DocumentationDefaults.shared)
        store.seedDocumentation()
        try render(PanelView(store: store), size: .init(width: 300, height: 450), name: "panel", output: output)
        try render(PresetsView(store: store), size: .init(width: 380, height: 440), name: "presets", output: output)
        try render(DDCSettings(device: store.displays[1], store: store), size: .init(width: 340, height: 590), name: "diagnostics", output: output)
        try render(ShortcutsView(store: store), size: .init(width: 380, height: 520), name: "shortcuts", output: output)
        try render(ShortcutsView(documenting: store, binding: DisplayShortcut.brightnessUp.defaultBinding),
                   size: .init(width: 380, height: 520), name: "shortcut-editor", output: output)
        store.shortcutRecorder.documentationState(listening: true)
        try render(ShortcutsView(documenting: store, binding: DisplayShortcut.brightnessUp.defaultBinding),
                   size: .init(width: 380, height: 520), name: "shortcut-listening", output: output)
        let recorded = ShortcutBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: [.control, .shift])
        store.shortcutRecorder.documentationState(recorded: recorded.label)
        try render(ShortcutsView(documenting: store, binding: recorded),
                   size: .init(width: 380, height: 520), name: "shortcut-recorded", output: output)
        let external = store.displays[1]
        precondition(store.renameDisplay(external, name: "Desk Display"))
        precondition(store.setFavorite(external, mode: external.modes[1].favorite!, enabled: true))
        precondition(store.setFavorite(external, mode: external.modes[0].favorite!, enabled: true))
        try render(DisplaySettingsView(device: external, store: store), size: .init(width: 360, height: 560), name: "display-settings", output: output)
        try render(DisplaySettingsView(device: external, store: store), size: .init(width: 360, height: 560), name: "display-settings-dark", output: output, dark: true)
        let advancedReport = """
        {"schema":1,"uuid":"00000000-0000-4000-8000-000000000002","transport":"standard","serviceCount":1,
        "delayMS":50,"contrast":{"status":"ok","current":70,"maximum":100,"attempts":1},
        "input":{"status":"ok","current":17,"maximum":0,"attempts":1}}
        """
        external.advancedProbe = AdvancedDDCProbe.parse(Data(advancedReport.utf8), expectedUUID: external.id, timing: .standard)
        external.contrast = 0.7
        precondition(external.advancedProbe != nil)
        try render(PanelView(documentingAdvanced: store), size: .init(width: 300, height: 660), name: "advanced", output: output)
        try render(PanelView(documentingAdvanced: store), size: .init(width: 300, height: 660), name: "advanced-dark", output: output, dark: true)
        print("Rendered 11 native UI examples with isolated sample data.")
    }

    @MainActor static func render<V: View>(_ view: V, size: NSSize, name: String, output: URL, dark: Bool = false) throws {
        let content = view.environment(\.colorScheme, dark ? .dark : .light).environment(\.controlActiveState, .active)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name).png"))
        window.contentView = nil
    }
}
