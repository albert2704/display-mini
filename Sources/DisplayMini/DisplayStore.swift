import AppKit
import Combine
import CoreGraphics
import DisplayCore

struct DisplayMode: Identifiable {
    let native: CGDisplayMode
    var id: Int32 { native.ioDisplayModeID }
    var descriptor: ModeDescriptor { .init(id: id, width: native.width, height: native.height, pixelWidth: native.pixelWidth, refresh: native.refreshRate) }
    var size: String { "\(native.width) × \(native.height)" }
    var favorite: FavoriteResolution? {
        .init(width: native.width, height: native.height, pixelWidth: native.pixelWidth,
              pixelHeight: native.pixelHeight, refresh: native.refreshRate)
    }
    var detail: String {
        let density = descriptor.hiDPI ? "HiDPI" : "Standard"
        return native.refreshRate > 0 ? "\(density) · \(Int(native.refreshRate.rounded())) Hz" : density
    }
}

@MainActor final class DisplayDevice: ObservableObject, Identifiable {
    let id: String
    var displayID: CGDirectDisplayID
    let builtIn: Bool
    @Published var name: String
    @Published var systemName: String
    @Published var connected = true
    @Published var brightness = 1.0
    @Published var volume: Double?
    @Published var brightnessMethod = "Software"
    @Published var reading = false
    @Published var needsControlRead = false
    @Published var writesInFlight = 0
    var writing: Bool { writesInFlight > 0 }
    @Published var error: String?
    @Published var ddcProbe: DDCProbe?
    @Published var ddcFailure: DDCFailure?
    @Published var lastDDCCheck: Date?
    @Published var ddcTiming: DDCTiming
    @Published var modes: [DisplayMode] = []
    @Published var sliderModes: [DisplayMode] = []
    @Published var currentModeID: Int32 = 0
    @Published var modeIndex = 0.0
    @Published var forceSoftware: Bool
    var nativeBrightness = false
    var ddcBrightness = false
    var brightnessMaximum = 100
    var volumeMaximum = 100
    var confirmedBrightness = 1.0
    var confirmedVolume: Double?
    var volumeBeforeMute: Double? {
        get { UserDefaults.standard.object(forKey: "volumeBeforeMute.\(id)") as? Double }
        set { UserDefaults.standard.set(newValue, forKey: "volumeBeforeMute.\(id)") }
    }
    func rememberVolume() {
        volumeBeforeMute = MonitorAudio.rememberedVolume(confirmed: confirmedVolume, previous: volumeBeforeMute)
    }
    var revision = 0
    var brightnessRevision = 0
    var volumeRevision = 0
    @Published var pendingBrightness: DispatchWorkItem?
    @Published var pendingVolume: DispatchWorkItem?
    var currentMode: DisplayMode? { modes.first { $0.id == currentModeID } }
    var softwareKey: String { "software.\(id)" }
    var softwareFraction: Double {
        get { UserDefaults.standard.object(forKey: softwareKey) as? Double ?? 1 }
        set { UserDefaults.standard.set(newValue, forKey: softwareKey) }
    }

    init(id: String, displayID: CGDirectDisplayID, name: String, builtIn: Bool) {
        self.id = id; self.displayID = displayID; self.name = name; self.systemName = name; self.builtIn = builtIn
        self.forceSoftware = UserDefaults.standard.bool(forKey: "forceSoftware.\(id)")
        self.ddcTiming = DDCTiming(saved: UserDefaults.standard.string(forKey: "ddcTiming.\(id)"))
    }
}

@MainActor final class DisplayStore: ObservableObject {
    @Published var displays: [DisplayDevice] = []
    @Published var message: String?
    @Published var connectionBusy = false
    @Published var pendingResolutionName: String?
    @Published var secondsRemaining = 0
    @Published var unresolvedRecovery = false
    @Published private(set) var presetLibrary = PresetLibrary()
    @Published private(set) var presetStorageError: String?
    @Published private(set) var applyingPresetName: String?
    @Published var presetMessage: String?
    @Published var shortcutsEnabled = UserDefaults.standard.object(forKey: "everydayShortcutsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(shortcutsEnabled, forKey: "everydayShortcutsEnabled") }
    }
    @Published var shortcutErrors: [String] = []
    @Published private(set) var shortcutPreferences = ShortcutPreferences()
    @Published private(set) var shortcutStorageMessage: String?
    @Published var shortcutEditMessage: String?
    let shortcutRecorder = ShortcutRecorder()
    var updateShortcutRegistration: ((ShortcutPreferences) -> String?)?
    private let shortcutDefaults: UserDefaults
    @Published private(set) var personalization = DisplayPersonalization()
    @Published private(set) var personalizationStorageError: String?
    @Published var personalizationMessage: String?
    private let personalizationDefaults: UserDefaults
    private var presetProgress: PresetProgress?
    private var presetSteps: [PresetPlan.Step] = []
    private var presetSkipped = 0
    private var deviceObservers = Set<AnyCancellable>()
    var controlsBusy: Bool { connectionBusy || pendingResolutionName != nil || applyingPresetName != nil }
    var canSavePreset: Bool {
        presetStorageError == nil && !controlsBusy && !sleeping && activeCount > 0 && displays.filter(\.connected).allSatisfy {
            !$0.reading && !$0.writing && !$0.needsControlRead && $0.pendingBrightness == nil && $0.pendingVolume == nil
        }
    }
    let native = NativeDisplays()
    let ddc = DDCClient()
    let dimming = DimmingWindows()
    private var observers: [NSObjectProtocol] = []
    private var refreshWork: DispatchWorkItem?
    private var resolutionTimer: Timer?
    private var recoveryTimer: Timer?
    private var sleeping = false
    private var shuttingDown = false
    private var nextRecoveryAttempt = Date.distantPast
    private var automaticRecoveryError: String?
    private var lastRecoveryTrace: String?
    private var recoveryActivity: NSObjectProtocol?
    private var physicalRecoveryAvailable = false
    private var connectionRevision = 0
    private var pendingResolution: (uuid: String, original: CGDisplayMode, requested: CGDisplayMode)?
    private var ownedDisconnects: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "ownedDisconnects") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "ownedDisconnects") }
    }
    var activeCount: Int { displays.filter(\.connected).count }

    init(startMonitoring: Bool = true, shortcutDefaults: UserDefaults = .standard, personalizationDefaults: UserDefaults = .standard) {
        self.shortcutDefaults = shortcutDefaults
        self.personalizationDefaults = personalizationDefaults
        if let data = personalizationDefaults.data(forKey: "displayPersonalization") {
            do { personalization = try DisplayPersonalization.decode(data) }
            catch { personalizationStorageError = error.localizedDescription }
        }
        if let data = shortcutDefaults.data(forKey: "shortcutBindings") {
            do { shortcutPreferences = try ShortcutPreferences.decode(data) }
            catch { shortcutStorageMessage = error.localizedDescription }
        }
        if let data = UserDefaults.standard.data(forKey: "displayPresets") {
            do { presetLibrary = try PresetLibrary.decode(data) }
            catch { presetStorageError = error.localizedDescription }
        }
        guard startMonitoring else { return }
        // Recover only connections this app owns, including after an unexpected exit.
        for uuid in ownedDisconnects {
            do { try native.setConnected(uuid: uuid, enabled: true); ownedDisconnects.remove(uuid) }
            catch { message = "A display needs reconnecting. Use Restore Displays or reconnect its cable." }
        }
        recoverSavedResolution()
        refresh()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = false; self?.scheduleRefresh() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = true; self?.cancelControlEdits() }
        })
    }

    func screen(for device: DisplayDevice) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == device.displayID }
    }

    private func scheduleRefresh() {
        if applyingPresetName != nil { cancelControlEdits() }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func refresh() {
        if applyingPresetName != nil { cancelControlEdits() }
        recoverBuiltInIfNeeded()
        var result: [DisplayDevice] = []
        for displayID in native.displayIDs() {
            let uuid = native.uuid(displayID)
            let builtIn = CGDisplayIsBuiltin(displayID) != 0
            let existing = displays.first { $0.id == uuid }
            // SkyLight also reports spare/offline display slots. Only expose a
            // disconnected row when it was a real screen seen by this app.
            guard CGDisplayIsOnline(displayID) != 0 || existing != nil || ownedDisconnects.contains(uuid) else { continue }
            let device = existing ?? DisplayDevice(id: uuid, displayID: displayID, name: builtIn ? "Built-in Display" : "External Display", builtIn: builtIn)
            device.displayID = displayID
            if let screen = screen(for: device) { device.systemName = builtIn ? "Built-in Display" : screen.localizedName }
            device.name = personalization.entry(for: uuid).name ?? device.systemName
            device.connected = CGDisplayIsOnline(displayID) != 0
            if device.connected {
                loadModes(device)
                if !device.reading && !device.writing && device.pendingBrightness == nil && device.pendingVolume == nil {
                    readControls(device)
                }
                if CGDisplayIsActive(displayID) != 0 {
                    ownedDisconnects.remove(uuid)
                    if device.builtIn, let error = automaticRecoveryError {
                        if message == error { message = nil }
                        automaticRecoveryError = nil
                    }
                }
            } else { dimming.remove(uuid) }
            result.append(device)
        }
        // Preserve a recovery row if an OS version omits a disabled display from its private list.
        for missing in displays where !result.contains(where: { $0.id == missing.id }) {
            missing.revision += 1
            missing.pendingBrightness?.cancel(); missing.pendingBrightness = nil
            missing.pendingVolume?.cancel(); missing.pendingVolume = nil
            dimming.remove(missing.id)
            if ownedDisconnects.contains(missing.id) { missing.connected = false; result.append(missing) }
        }
        displays = result.sorted { a, b in a.builtIn != b.builtIn ? a.builtIn : a.name < b.name }
        deviceObservers.removeAll()
        for device in displays {
            device.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &deviceObservers)
        }
        updateRecoveryTimer()
    }

    private func recoverBuiltInIfNeeded() {
        guard !shuttingDown, !sleeping, !connectionBusy else {
            traceRecovery("paused: shutdown=\(shuttingDown) sleep=\(sleeping) busy=\(connectionBusy)")
            return
        }
        let owned = ownedDisconnects
        guard displays.contains(where: { $0.builtIn && owned.contains($0.id) }) else {
            traceRecovery("no owned built-in row: owned=\(owned.count) rows=\(displays.count)")
            return
        }
        // Query the OS afresh. Published rows may still describe the unplugged screen.
        var states = native.displayIDs().map { id in
            let uuid = native.uuid(id)
            return DisplayConnectionState(uuid: uuid,
                builtIn: displays.first(where: { $0.id == uuid })?.builtIn ?? (CGDisplayIsBuiltin(id) != 0),
                online: CGDisplayIsOnline(id) != 0, active: CGDisplayIsActive(id) != 0)
        }
        // A disabled panel may be temporarily absent from the private display list.
        for device in displays where device.builtIn && owned.contains(device.id) && !states.contains(where: { $0.uuid == device.id }) {
            states.append(.init(uuid: device.id, builtIn: true, online: false, active: false))
        }
        let lid = native.lidClosed
        let links = native.activeExternalLinkCount
        let candidates = BuiltInDisplayRecovery.candidates(states, owned: owned, lidClosed: lid,
            sleeping: sleeping, connectionBusy: connectionBusy,
            physicalExternalLost: physicalRecoveryAvailable && links == 0)
        traceRecovery("check: lid=\(lid.map(String.init) ?? "unknown") activeExternal=\(states.filter { !$0.builtIn && $0.online && $0.active }.count) physicalLinks=\(links.map(String.init) ?? "unknown") hardwareRecovery=\(physicalRecoveryAvailable) ownedPanels=\(states.filter { $0.builtIn && owned.contains($0.uuid) }.count) candidates=\(candidates.count)")
        guard !candidates.isEmpty, Date() >= nextRecoveryAttempt else { return }
        nextRecoveryAttempt = Date().addingTimeInterval(2)
        for uuid in candidates {
            do {
                try native.setConnected(uuid: uuid, enabled: true)
                traceRecovery("enable transaction accepted")
                // Keep ownership until a later refresh confirms that the panel is active.
                scheduleRefresh()
            } catch {
                let error = "Could not automatically restore the built-in display. Recovery will retry. \(error.localizedDescription)"
                automaticRecoveryError = error; message = error
                traceRecovery("enable failed: \(error)")
            }
        }
    }

    private func traceRecovery(_ event: String) {
        guard event != lastRecoveryTrace else { return }
        lastRecoveryTrace = event
        var events = UserDefaults.standard.stringArray(forKey: "recoveryTrace") ?? []
        events.append("\(ISO8601DateFormatter().string(from: Date())) \(event)")
        UserDefaults.standard.set(Array(events.suffix(40)), forKey: "recoveryTrace")
    }

    private func updateRecoveryTimer() {
        guard displays.contains(where: { $0.builtIn && ownedDisconnects.contains($0.id) }) else {
            recoveryTimer?.invalidate(); recoveryTimer = nil
            if let recoveryActivity { ProcessInfo.processInfo.endActivity(recoveryActivity) }
            recoveryActivity = nil
            physicalRecoveryAvailable = false
            return
        }
        guard recoveryTimer == nil else { return }
        recoveryActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Restore the built-in display when an external monitor is unplugged")
        // A fallback is needed when unplugging the last screen produces no AppKit event.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshForRecovery() }
        }
        timer.tolerance = 0.3
        recoveryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        traceRecovery("recovery timer started")
    }

    private func refreshForRecovery() {
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: Date()), forKey: "recoveryHeartbeat")
        guard !shuttingDown, !sleeping else {
            traceRecovery("timer paused: shutdown=\(shuttingDown) sleep=\(sleeping)")
            return
        }
        recoverBuiltInIfNeeded()
        // Normal control reads are left to screen notifications and explicit refresh.
        // A successful asynchronous enable is confirmed even if AppKit emits no event.
        if displays.contains(where: { $0.builtIn && ownedDisconnects.contains($0.id) &&
            native.currentID(for: $0.id).map { CGDisplayIsOnline($0) != 0 && CGDisplayIsActive($0) != 0 } == true }) {
            refresh()
        }
    }

    func displayName(for uuid: String, fallback: String) -> String {
        personalization.entry(for: uuid).name ?? displays.first(where: { $0.id == uuid })?.systemName ?? fallback
    }

    @discardableResult func renameDisplay(_ device: DisplayDevice, name: String) -> Bool {
        editPersonalization { try $0.rename(uuid: device.id, name: name) }
    }

    func favoriteModes(_ device: DisplayDevice) -> [DisplayMode] {
        guard device.connected else { return [] }
        return personalization.entry(for: device.id).favorites.compactMap { favorite in
            device.modes.first { $0.favorite == favorite }
        }
    }

    @discardableResult func setFavorite(_ device: DisplayDevice, mode: FavoriteResolution, enabled: Bool) -> Bool {
        guard !enabled || (device.connected && device.modes.contains(where: { $0.favorite == mode })) else {
            personalizationMessage = "This resolution is no longer available. Refresh the display and try again."
            return false
        }
        return editPersonalization { try $0.setFavorite(uuid: device.id, mode: mode, enabled: enabled) }
    }

    func applyFavorite(_ device: DisplayDevice, favorite: FavoriteResolution) {
        guard !controlsBusy, !sleeping else { return }
        guard device.connected, displays.contains(where: { $0 === device }),
              personalization.entry(for: device.id).favorites.contains(favorite),
              let currentID = native.currentID(for: device.id), currentID == device.displayID else {
            message = "This favorite resolution is not currently available."
            return
        }
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(currentID, options) as? [CGDisplayMode] ?? []
        guard let mode = modes.filter({ $0.isUsableForDesktopGUI() }).map({ DisplayMode(native: $0) })
            .first(where: { $0.favorite == favorite }) else {
            message = "This favorite resolution is not currently available."
            return
        }
        changeResolution(device, mode: mode)
    }

    private func editPersonalization(_ edit: (inout DisplayPersonalization) throws -> Void) -> Bool {
        guard personalizationStorageError == nil else { return false }
        do {
            var updated = personalization
            try edit(&updated)
            let data = try JSONEncoder().encode(updated)
            personalizationDefaults.set(data, forKey: "displayPersonalization")
            personalization = updated; personalizationMessage = nil
            for device in displays { device.name = updated.entry(for: device.id).name ?? device.systemName }
            return true
        } catch { personalizationMessage = error.localizedDescription; return false }
    }

    func resetUnreadablePersonalization() {
        guard personalizationStorageError != nil else { return }
        personalizationDefaults.set(personalizationDefaults.data(forKey: "displayPersonalization"), forKey: "displayPersonalizationBackup")
        personalizationDefaults.removeObject(forKey: "displayPersonalization")
        personalization = DisplayPersonalization(); personalizationStorageError = nil
        personalizationMessage = "Created empty display settings. The unreadable data was backed up locally."
        for device in displays { device.name = device.systemName }
    }

    private func loadModes(_ device: DisplayDevice) {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(device.displayID, options) as? [CGDisplayMode]) ?? []
        var seen = Set<Int32>()
        device.modes = modes.filter { $0.width >= 640 && $0.height >= 400 && $0.isUsableForDesktopGUI() && seen.insert($0.ioDisplayModeID).inserted }
            .map { DisplayMode(native: $0) }
            .sorted { ($0.native.width, $0.native.height, $0.native.pixelWidth, $0.native.refreshRate) < ($1.native.width, $1.native.height, $1.native.pixelWidth, $1.native.refreshRate) }
        let current = CGDisplayCopyDisplayMode(device.displayID).map { DisplayMode(native: $0) }
        if let current, !device.modes.contains(where: { $0.id == current.id }) { device.modes.append(current) }
        device.currentModeID = current?.id ?? 0
        let descriptors = ModeSelection.sliderModes(device.modes.map(\.descriptor), current: current?.descriptor)
        device.sliderModes = descriptors.compactMap { descriptor in device.modes.first { $0.id == descriptor.id } }
        device.modeIndex = Double(device.sliderModes.firstIndex { $0.id == device.currentModeID } ?? 0)
    }

    private func readControls(_ device: DisplayDevice) {
        if (device.builtIn || CGDisplayVendorNumber(device.displayID) == 1552),
           let value = native.brightness(device.displayID), !device.forceSoftware {
            device.nativeBrightness = true
            device.brightnessMethod = "Combined"
            device.brightness = ControlMath.combinedValue(hardware: value, software: device.softwareFraction)
        } else {
            device.nativeBrightness = false
            if !device.ddcBrightness || device.forceSoftware {
                device.brightnessMethod = "Software"
                device.brightness = device.softwareFraction
            }
        }
        device.confirmedBrightness = device.brightness
        applyDimming(device, fraction: device.softwareFraction)
        guard !device.builtIn else { device.needsControlRead = false; return }
        device.reading = true
        let revision = device.revision
        ddc.read(uuid: device.id, timing: device.ddcTiming) { [weak self, weak device] result in
            guard let self, let device else { return }
            device.reading = false
            guard device.connected, device.revision == revision else { self.reconcileControlsIfNeeded(device); return }
            device.needsControlRead = false
            device.lastDDCCheck = Date()
            switch result {
            case .success(let probe): device.ddcProbe = probe; device.ddcFailure = nil
            case .failure(let error): device.ddcProbe = nil; device.ddcFailure = error
            }
            let brightness = device.ddcProbe?.brightness.fraction
            let volume = device.ddcProbe?.volume.fraction
            device.ddcBrightness = brightness != nil
            device.brightnessMaximum = device.ddcProbe?.brightness.maximum ?? 100
            device.volumeMaximum = device.ddcProbe?.volume.maximum ?? 100
            device.volume = volume; device.confirmedVolume = volume
            device.rememberVolume()
            if !device.forceSoftware && !device.nativeBrightness, let brightness {
                device.brightnessMethod = "Combined"
                device.brightness = ControlMath.combinedValue(hardware: brightness, software: device.softwareFraction)
                device.confirmedBrightness = device.brightness
            } else if !device.nativeBrightness || device.forceSoftware {
                device.brightnessMethod = "Software"
                device.brightness = device.softwareFraction
                device.confirmedBrightness = device.brightness
            }
            self.objectWillChange.send()
        }
    }

    private func reconcileControlsIfNeeded(_ device: DisplayDevice) {
        guard device.needsControlRead, device.connected, !shuttingDown, !sleeping,
              !device.reading, !device.writing, device.pendingBrightness == nil, device.pendingVolume == nil else { return }
        readControls(device)
    }

    private func applyDimming(_ device: DisplayDevice, fraction: Double) {
        dimming.set(uuid: device.id, screen: screen(for: device), fraction: fraction)
    }

    func setBrightness(_ device: DisplayDevice, _ value: Double) {
        guard !controlsBusy, !sleeping, !device.needsControlRead else { return }
        writeBrightness(device, value)
    }

    private func writeBrightness(_ device: DisplayDevice, _ value: Double, completion: @escaping (Bool) -> Void = { _ in }) {
        guard device.connected, pendingResolution == nil, !connectionBusy else { completion(false); return }
        device.revision += 1; device.brightnessRevision += 1; device.error = nil
        device.brightness = ControlMath.clamp(value)
        device.pendingBrightness?.cancel()
        let work = DispatchWorkItem { [weak self, weak device] in
            guard let self, let device, device.connected else { completion(false); return }
            device.pendingBrightness = nil
            defer { self.reconcileControlsIfNeeded(device) }
            let requested = device.brightness
            let parts = ControlMath.combined(requested)
            let softwareOnly = device.forceSoftware || (!device.nativeBrightness && !device.ddcBrightness)
            let software = softwareOnly ? max(0.03, requested) : parts.software
            if softwareOnly {
                device.softwareFraction = software; device.confirmedBrightness = requested
                self.applyDimming(device, fraction: software)
                completion(true)
            } else if device.nativeBrightness {
                do {
                    try self.native.setBrightness(device.displayID, value: max(0.01, parts.hardware))
                    device.softwareFraction = software; device.confirmedBrightness = requested
                    self.applyDimming(device, fraction: software)
                    completion(true)
                } catch { device.brightness = device.confirmedBrightness; device.error = error.localizedDescription; completion(false) }
            } else {
                device.writesInFlight += 1
                let revision = device.brightnessRevision
                self.ddc.write(uuid: device.id, timing: device.ddcTiming, attribute: "luminance", value: ControlMath.rawValue(fraction: parts.hardware, maximum: device.brightnessMaximum)) { [weak self, weak device] result in
                    guard let self, let device else { completion(false); return }
                    defer { self.reconcileControlsIfNeeded(device) }
                    device.writesInFlight = max(0, device.writesInFlight - 1)
                    guard device.brightnessRevision == revision, device.connected else {
                        self.reconcileControlsIfNeeded(device); completion(false); return
                    }
                    if case .success = result {
                        device.confirmedBrightness = requested
                        device.softwareFraction = software; self.applyDimming(device, fraction: software)
                        completion(true)
                    } else if case .failure(let error) = result {
                        device.brightness = device.confirmedBrightness; device.error = error.localizedDescription
                        completion(false)
                    }
                }
            }
        }
        device.pendingBrightness = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func setVolume(_ device: DisplayDevice, _ value: Double) {
        guard !controlsBusy, !sleeping, !device.needsControlRead else { return }
        writeVolume(device, value)
    }

    private func writeVolume(_ device: DisplayDevice, _ value: Double, completion: @escaping (Bool) -> Void = { _ in }) {
        guard device.connected, device.volume != nil, !connectionBusy, pendingResolution == nil else { completion(false); return }
        device.revision += 1; device.volumeRevision += 1; device.error = nil; device.volume = ControlMath.clamp(value)
        device.pendingVolume?.cancel()
        let work = DispatchWorkItem { [weak self, weak device] in
            guard let self, let device, device.connected, let requested = device.volume else { completion(false); return }
            device.pendingVolume = nil; device.writesInFlight += 1
            let revision = device.volumeRevision
            self.ddc.write(uuid: device.id, timing: device.ddcTiming, attribute: "volume", value: ControlMath.rawValue(fraction: requested, maximum: device.volumeMaximum)) { [weak self, weak device] result in
                guard let self, let device else { completion(false); return }
                defer { self.reconcileControlsIfNeeded(device) }
                device.writesInFlight = max(0, device.writesInFlight - 1)
                guard device.volumeRevision == revision, device.connected else {
                    self.reconcileControlsIfNeeded(device); completion(false); return
                }
                if case .success = result { device.confirmedVolume = requested; device.rememberVolume(); completion(true) }
                else if case .failure(let error) = result {
                    device.volume = device.confirmedVolume; device.error = error.localizedDescription
                    completion(false)
                }
            }
        }
        device.pendingVolume = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func toggleMute(_ device: DisplayDevice) {
        guard canConfigureDDC(device), let volume = device.confirmedVolume else { return }
        device.rememberVolume()
        setVolume(device, MonitorAudio.toggledVolume(current: volume, remembered: device.volumeBeforeMute))
    }

    func shortcutKeys(_ action: DisplayShortcut) -> String { shortcutPreferences[action].label }

    @discardableResult func saveShortcut(_ action: DisplayShortcut, binding: ShortcutBinding) -> Bool {
        do {
            var preferences = shortcutPreferences
            try preferences.set(action, binding: binding)
            return saveShortcutPreferences(preferences)
        } catch { shortcutEditMessage = error.localizedDescription; return false }
    }

    @discardableResult func resetShortcuts() -> Bool { saveShortcutPreferences(ShortcutPreferences()) }

    private func saveShortcutPreferences(_ preferences: ShortcutPreferences) -> Bool {
        guard let updateShortcutRegistration else { shortcutEditMessage = "Keyboard shortcuts are not ready yet."; return false }
        do {
            let data = try JSONEncoder().encode(preferences)
            if let error = updateShortcutRegistration(preferences) {
                shortcutEditMessage = "\(error) Your previous bindings are still active."
                return false
            }
            if shortcutStorageMessage != nil {
                shortcutDefaults.set(shortcutDefaults.data(forKey: "shortcutBindings"), forKey: "shortcutBindingsBackup")
            }
            shortcutDefaults.set(data, forKey: "shortcutBindings")
            shortcutPreferences = preferences; shortcutStorageMessage = nil; shortcutEditMessage = nil
            return true
        } catch { shortcutEditMessage = error.localizedDescription; return false }
    }

    /// Returns false when the panel should show why the action could not run.
    func performShortcut(_ action: DisplayShortcut) -> Bool {
        guard shortcutsEnabled, !sleeping else { return true }
        if [.preset1, .preset2, .preset3].contains(action) {
            let index = Int(action.rawValue - DisplayShortcut.preset1.rawValue)
            guard presetLibrary.presets.indices.contains(index) else {
                message = "Save a preset in Presets before using \(shortcutKeys(action))."; return false
            }
            let applied = applyPreset(presetLibrary.presets[index])
            if !applied { message = presetMessage }
            return applied
        }
        guard !controlsBusy else { message = "Wait for the current display change to finish."; return false }
        let point = NSEvent.mouseLocation
        guard let target = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let number = target.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let device = displays.first(where: { $0.displayID == number.uint32Value && $0.connected }) else {
            message = "No connected display was found under the pointer. Refresh displays and try again."; return false
        }
        guard !device.reading, !device.needsControlRead else { message = "\(device.name) is still checking its controls. Try again shortly."; return false }
        switch action {
        case .brightnessUp, .brightnessDown:
            setBrightness(device, device.brightness + (action == .brightnessUp ? 0.05 : -0.05))
        case .volumeUp, .volumeDown:
            guard let volume = device.volume else { message = "Monitor volume is unavailable for \(device.name)."; return false }
            setVolume(device, volume + (action == .volumeUp ? 0.05 : -0.05))
        case .mute:
            guard device.volume != nil else { message = "Monitor volume is unavailable for \(device.name)."; return false }
            guard canConfigureDDC(device) else { message = "Wait for \(device.name)’s volume change to finish."; return false }
            toggleMute(device)
        default: return true
        }
        return true
    }

    @discardableResult func savePreset(name: String) -> Bool {
        guard canSavePreset else { presetMessage = "Wait for display controls to finish, then save."; return false }
        return editPresets { library in
            try library.save(name: name, displays: displays.filter(\.connected).map {
                PresetDisplay(uuid: $0.id, name: $0.name, brightness: $0.confirmedBrightness, volume: $0.confirmedVolume)
            })
        }
    }

    @discardableResult func renamePreset(_ id: UUID, name: String) -> Bool {
        editPresets { try $0.rename(id: id, name: name) }
    }
    func deletePreset(_ id: UUID) { _ = editPresets { $0.delete(id: id) } }
    private func editPresets(_ edit: (inout PresetLibrary) throws -> Void) -> Bool {
        guard presetStorageError == nil, applyingPresetName == nil else { return false }
        do {
            var library = presetLibrary
            try edit(&library)
            let data = try JSONEncoder().encode(library)
            UserDefaults.standard.set(data, forKey: "displayPresets")
            presetLibrary = library; presetMessage = nil
            return true
        } catch { presetMessage = error.localizedDescription; return false }
    }
    func resetUnreadablePresets() {
        guard presetStorageError != nil else { return }
        UserDefaults.standard.set(UserDefaults.standard.data(forKey: "displayPresets"), forKey: "displayPresetsBackup")
        UserDefaults.standard.removeObject(forKey: "displayPresets")
        presetLibrary = PresetLibrary(); presetStorageError = nil; presetMessage = "Created an empty library. The unreadable data was backed up locally."
    }

    @discardableResult func applyPreset(_ preset: DisplayPreset) -> Bool {
        guard canSavePreset else { presetMessage = "Wait for display controls to finish, then apply."; return false }
        let available = Dictionary(uniqueKeysWithValues: displays.filter(\.connected).map { ($0.id, $0.confirmedVolume != nil) })
        let plan = PresetPlan(preset: preset, available: available)
        guard !plan.steps.isEmpty else { presetMessage = "None of this preset’s displays are connected."; return false }
        presetProgress = PresetProgress(steps: plan.steps)
        presetSteps = plan.steps; presetSkipped = plan.skippedControls
        applyingPresetName = preset.name; presetMessage = nil
        runNextPresetStep()
        return true
    }

    private func runNextPresetStep() {
        guard let progress = presetProgress, !presetSteps.isEmpty else { return }
        let step = presetSteps.removeFirst()
        let complete: (Bool) -> Void = { [weak self] success in
            guard let self, self.presetProgress?.finish(token: progress.token, step: step.id, success: success) == true else { return }
            if let current = self.presetProgress, current.pending.isEmpty {
                let name = self.applyingPresetName ?? "Preset"
                let skipped = self.presetSkipped > 0 ? " \(self.presetSkipped) unavailable controls skipped." : ""
                self.presetMessage = current.failures == 0 ? "Applied “\(name)”.\(skipped)" : "“\(name)” finished with \(current.failures) failed changes. Check the display errors.\(skipped)"
                self.message = self.presetMessage
                self.presetProgress = nil; self.applyingPresetName = nil
            } else { self.runNextPresetStep() }
        }
        guard let device = displays.first(where: { $0.id == step.displayUUID && $0.connected }) else { complete(false); return }
        switch step.control {
        case .brightness: writeBrightness(device, step.value, completion: complete)
        case .volume: writeVolume(device, step.value, completion: complete)
        }
    }

    func setSoftwareOnly(_ device: DisplayDevice, _ value: Bool) {
        guard canConfigureDDC(device) else { return }
        device.revision += 1; device.brightnessRevision += 1
        device.pendingBrightness?.cancel(); device.pendingBrightness = nil
        device.forceSoftware = value
        UserDefaults.standard.set(value, forKey: "forceSoftware.\(device.id)")
        device.softwareFraction = 1; dimming.remove(device.id)
        readControls(device)
    }

    func canConfigureDDC(_ device: DisplayDevice) -> Bool {
        device.connected && !device.reading && !device.writing && !device.needsControlRead && device.pendingBrightness == nil &&
        device.pendingVolume == nil && !controlsBusy && !sleeping
    }

    func retryDDC(_ device: DisplayDevice) {
        guard canConfigureDDC(device) else { return }
        device.error = nil; readControls(device)
    }

    func setDDCTiming(_ device: DisplayDevice, _ timing: DDCTiming) {
        guard canConfigureDDC(device), timing != device.ddcTiming else { return }
        device.ddcTiming = timing
        UserDefaults.standard.set(timing.rawValue, forKey: "ddcTiming.\(device.id)")
        device.revision += 1
        readControls(device)
    }

    func diagnosticReport(for device: DisplayDevice) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        var lines = ["Display Mini connection report", "App: \(version)",
                     "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
                     "Display kind: \(device.builtIn ? "Built-in" : "External")",
                     String(format: "Vendor/model: %04X/%04X", CGDisplayVendorNumber(device.displayID), CGDisplayModelNumber(device.displayID)),
                     "Connected: \(device.connected)", "Resolution: \(device.currentMode?.size ?? "Unavailable")",
                     "Brightness mode: \(device.forceSoftware ? "Software only" : device.nativeBrightness ? "Native + software" : device.ddcBrightness ? "DDC + software" : "Software fallback")",
                     "Timing profile: \(device.ddcTiming.title)"]
        if let date = device.lastDDCCheck { lines.append("Last check: \(ISO8601DateFormatter().string(from: date))") }
        if let probe = device.ddcProbe { lines += probe.diagnosticLines }
        if let failure = device.ddcFailure { lines.append("Check failed: \(failure.localizedDescription)") }
        if device.lastDDCCheck == nil { lines.append("DDC has not been checked yet.") }
        lines.append("Serial numbers, UUIDs, display names and local paths are omitted. No data was uploaded.")
        return lines.joined(separator: "\n")
    }

    func toggleConnection(_ device: DisplayDevice, enabled: Bool) {
        guard !controlsBusy, !sleeping else { return }
        guard ControlMath.mayDisconnect(isEnabled: !enabled, activeCount: activeCount, pending: connectionBusy) else { device.error = "Keep at least one display connected."; return }
        device.error = nil; connectionBusy = true
        connectionRevision += 1
        let operation = connectionRevision
        device.revision += 1; device.brightnessRevision += 1; device.volumeRevision += 1
        device.pendingBrightness?.cancel(); device.pendingBrightness = nil
        device.pendingVolume?.cancel(); device.pendingVolume = nil
        if !enabled {
            if device.builtIn {
                let externalCount = native.displayIDs().filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayIsOnline($0) != 0 && CGDisplayIsActive($0) != 0 }.count
                // Only trust hardware loss when these ports cover the active replacement screens.
                physicalRecoveryAvailable = externalCount > 0 && native.activeExternalLinkCount == externalCount
            }
            ownedDisconnects.insert(device.id); dimming.remove(device.id); updateRecoveryTimer()
        }
        traceRecovery("connection request: builtin=\(device.builtIn) enable=\(enabled)")
        do {
            try native.setConnected(uuid: device.id, enabled: enabled)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak device] in
                guard let self, self.connectionRevision == operation else { return }
                self.connectionBusy = false
                self.refresh()
                if let device {
                    if device.connected != enabled { device.error = "macOS did not change the connection. Reconnect the cable if needed." }
                    else if enabled { self.ownedDisconnects.remove(device.id) }
                }
            }
        } catch {
            connectionBusy = false; device.error = error.localizedDescription
            if !enabled { ownedDisconnects.remove(device.id) }
            updateRecoveryTimer()
        }
    }

    func changeResolution(_ device: DisplayDevice, mode: DisplayMode) {
        guard !controlsBusy, !sleeping, device.connected,
              mode.id != device.currentModeID, let original = CGDisplayCopyDisplayMode(device.displayID) else { return }
        guard UserDefaults.standard.dictionary(forKey: "resolutionRecovery") == nil else {
            unresolvedRecovery = true
            message = "A previous resolution still needs recovery. Restore Displays, or keep the current resolution before choosing another."
            return
        }
        device.error = nil
        UserDefaults.standard.set([
            "uuid": device.id, "modeID": Int(original.ioDisplayModeID),
            "width": original.width, "height": original.height,
            "pixelWidth": original.pixelWidth, "refresh": original.refreshRate
        ], forKey: "resolutionRecovery")
        do {
            try native.setMode(device.displayID, mode: mode.native)
            pendingResolution = (device.id, original, mode.native)
            pendingResolutionName = device.name; secondsRemaining = 15
            loadModes(device)
            resolutionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }; self.secondsRemaining -= 1
                    if self.secondsRemaining <= 0 { self.revertResolution() }
                }
            }
            if let resolutionTimer { RunLoop.main.add(resolutionTimer, forMode: .common) }
        } catch {
            UserDefaults.standard.removeObject(forKey: "resolutionRecovery")
            device.error = error.localizedDescription; loadModes(device)
        }
    }

    func commitSliderResolution(_ device: DisplayDevice) {
        guard !device.sliderModes.isEmpty else { return }
        let index = min(device.sliderModes.count - 1, max(0, Int(device.modeIndex.rounded())))
        changeResolution(device, mode: device.sliderModes[index])
    }

    func keepResolution() {
        guard let pending = pendingResolution, let id = native.currentID(for: pending.uuid) else { revertResolution(); return }
        do { try native.setMode(id, mode: pending.requested, permanent: true); clearResolution(); refresh() }
        catch { message = error.localizedDescription; revertResolution() }
    }

    func revertResolution() {
        guard let pending = pendingResolution else { return }
        resolutionTimer?.invalidate(); resolutionTimer = nil
        secondsRemaining = 0
        if let id = native.currentID(for: pending.uuid) {
            do { try native.setMode(id, mode: pending.original); clearResolution(); refresh() }
            catch { message = "Could not restore resolution. Reconnect the display and press Revert to retry. \(error.localizedDescription)" }
        } else {
            message = "Reconnect the display and press Revert to restore its previous resolution."
        }
    }

    private func clearResolution() {
        resolutionTimer?.invalidate(); resolutionTimer = nil
        pendingResolution = nil; pendingResolutionName = nil; secondsRemaining = 0
        unresolvedRecovery = false
        UserDefaults.standard.removeObject(forKey: "resolutionRecovery")
    }

    func restoreDisplays() {
        connectionRevision += 1; connectionBusy = false
        cancelControlEdits()
        for uuid in ownedDisconnects {
            do { try native.setConnected(uuid: uuid, enabled: true); ownedDisconnects.remove(uuid) }
            catch { message = error.localizedDescription }
        }
        revertResolution()
        if pendingResolution == nil { recoverSavedResolution() }
        for device in displays {
            device.softwareFraction = 1
            if device.connected && device.brightness < ControlMath.softwareThreshold { writeBrightness(device, 0.6) }
        }
        dimming.removeAll(); scheduleRefresh()
    }

    func shutdown() {
        shuttingDown = true
        refreshWork?.cancel()
        recoveryTimer?.invalidate(); recoveryTimer = nil
        if let recoveryActivity { ProcessInfo.processInfo.endActivity(recoveryActivity) }
        recoveryActivity = nil
        cancelControlEdits()
        for uuid in ownedDisconnects {
            if (try? native.setConnected(uuid: uuid, enabled: true)) != nil { ownedDisconnects.remove(uuid) }
        }
        revertResolution()
        dimming.removeAll()
    }

    private func cancelControlEdits() {
        if let name = applyingPresetName {
            presetMessage = "“\(name)” was interrupted. Some changes may already have reached the monitors."
            message = presetMessage
        }
        presetProgress = nil; presetSteps = []; applyingPresetName = nil
        for device in displays {
            device.needsControlRead = true
            device.revision += 1; device.brightnessRevision += 1; device.volumeRevision += 1
            device.pendingBrightness?.cancel(); device.pendingBrightness = nil
            device.pendingVolume?.cancel(); device.pendingVolume = nil
            device.brightness = device.confirmedBrightness; device.volume = device.confirmedVolume
        }
    }

    private func recoverSavedResolution() {
        guard let saved = UserDefaults.standard.dictionary(forKey: "resolutionRecovery"),
              let uuid = saved["uuid"] as? String else { return }
        unresolvedRecovery = true
        guard let id = native.currentID(for: uuid), CGDisplayIsOnline(id) != 0 else {
            message = "Reconnect your display and use Restore Displays to recover its previous resolution."
            return
        }
        let modes = CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary) as? [CGDisplayMode] ?? []
        let original = modes.first { mode in
            mode.width == saved["width"] as? Int && mode.height == saved["height"] as? Int &&
            mode.pixelWidth == saved["pixelWidth"] as? Int && abs(mode.refreshRate - (saved["refresh"] as? Double ?? 0)) < 0.5
        }
        guard let original else { message = "The previous resolution is no longer available. Choose one in macOS Displays settings."; return }
        do { try native.setMode(id, mode: original); UserDefaults.standard.removeObject(forKey: "resolutionRecovery"); unresolvedRecovery = false }
        catch { message = "Could not recover the previous resolution: \(error.localizedDescription)" }
    }

    func keepCurrentResolution() {
        guard pendingResolution == nil else { return }
        UserDefaults.standard.removeObject(forKey: "resolutionRecovery")
        unresolvedRecovery = false; message = nil
    }
}
