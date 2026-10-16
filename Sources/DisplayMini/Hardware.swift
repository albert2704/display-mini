import AppKit
import CoreGraphics
import Darwin
import DisplayCore
import IOKit

enum DisplayFailure: LocalizedError {
    case notAttached
    case message(String)
    var errorDescription: String? {
        switch self {
        case .notAttached: return "Display is no longer attached."
        case .message(let text): return text
        }
    }
}

final class NativeDisplays {
    typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    typealias SetEnabled = @convention(c) (CGDisplayConfigRef?, UInt32, Bool) -> CGError
    typealias GetList = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> CGError
    private let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private var knownIdentities: [String: DisplayIdentity] = {
        guard let data = UserDefaults.standard.data(forKey: "displayIdentities"),
              let values = try? JSONDecoder().decode([String: DisplayIdentity].self, from: data) else { return [:] }
        return values
    }()
    private var lastConnectionIdentityTrace: String?
    private struct PanelWakeSession {
        let target: BuiltInPanelTarget
        let generation = UUID()
        var budget = PanelWakeBudget()
    }
    // The kernel service is captured while the panel is still positively identified.
    // It is never reconstructed from a persisted display ID after relaunch.
    private var panelWakeSessions: [String: PanelWakeSession] = [:]
    private let panelWakeQueue = DispatchQueue(label: "dev.albert.DisplayMini.panelWake", qos: .userInitiated)

    private func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ names: [String], as: T.Type) -> T? {
        guard let handle else { return nil }
        for name in names { if let pointer = dlsym(handle, name) { return unsafeBitCast(pointer, to: T.self) } }
        return nil
    }

    var canConnect: Bool { symbol(skyLight, ["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"], as: SetEnabled.self) != nil }

    var lidClosed: Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }

    var activeExternalLinkCount: Int? {
        for name in ["AppleDCPDPTXRemotePortUFP", "AppleATCDPAltModePort"] {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            var states: [Bool] = []
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                let hints = IORegistryEntryCreateCFProperty(service, "DisplayHints" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
                let events = IORegistryEntryCreateCFProperty(service, "EventLog" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]] ?? []
                if let active = ExternalLinkState.active(hints: hints, events: events) { states.append(active) }
            }
            if !states.isEmpty { return states.filter { $0 }.count }
        }
        return nil
    }

    func displayIDs() -> [CGDirectDisplayID] {
        displayList().ids
    }

    private func displayList() -> (ids: [CGDirectDisplayID], source: String) {
        var ids = [UInt32](repeating: 0, count: 64), count: UInt32 = 0
        if let list = symbol(skyLight, ["SLSGetDisplayList", "CGSGetDisplayList"], as: GetList.self),
           list(64, &ids, &count) == .success { return (Array(ids.prefix(Int(min(count, 64)))), "private") }
        guard CGGetOnlineDisplayList(64, &ids, &count) == .success else { return ([], "unavailable") }
        return (Array(ids.prefix(Int(min(count, 64)))), "online")
    }

    private func identity(_ id: CGDirectDisplayID) -> DisplayIdentity {
        DisplayIdentity(displayID: id, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
    }

    private func rawUUID(_ id: CGDirectDisplayID) -> String? {
        guard let value = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, value) as String
    }

    func uuid(_ id: CGDirectDisplayID) -> String {
        let hardware = identity(id)
        if let uuid = rawUUID(id) {
            if hardware.vendor != 0 && knownIdentities[uuid] != hardware {
                knownIdentities[uuid] = hardware
                if let data = try? JSONEncoder().encode(knownIdentities) { UserDefaults.standard.set(data, forKey: "displayIdentities") }
            }
            return uuid
        }
        let known = knownIdentities.filter { $0.value.matchesHardware(hardware) }
        return known.count == 1 ? known.first!.key : "display-\(id)"
    }

    func currentID(for uuid: String) -> CGDirectDisplayID? {
        currentID(for: uuid, connectionChange: nil)
    }

    private func currentID(for uuid: String, connectionChange: Bool?) -> CGDirectDisplayID? {
        let list = displayList(), ids = list.ids
        let expected = knownIdentities[uuid]
        var exactStates: [UInt32: String] = [:], fallbackStates: [UInt32: String] = [:]
        func uuidState(_ value: String?) -> String { value == nil ? "absent" : (value == uuid ? "exact" : "other") }
        if let exact = ids.first(where: { id in
            let value = rawUUID(id)
            exactStates[id] = uuidState(value)
            return value == uuid
        }) {
            if let enabled = connectionChange { traceConnectionIdentity("enable=\(enabled) source=\(list.source) count=\(ids.count) result=exactUUID") }
            return exact
        }
        let candidates: [DisplayIdentity]
        if expected != nil {
            candidates = ids.filter { id in
                let value = rawUUID(id)
                fallbackStates[id] = uuidState(value)
                return value == nil
            }.map(identity)
        } else { candidates = [] }
        let result = expected.flatMap { DisplayIdentity.resolve($0, among: candidates) }
        if let enabled = connectionChange {
            // Record the UUID reads and hardware values used by this lookup, not
            // a later re-enumeration that could miss a transient failure.
            func fields(_ value: DisplayIdentity?) -> String {
                guard let value else { return "unknown" }
                return "\(value.vendor != 0 && value.vendor != .max)/\(value.model != 0 && value.model != .max)/\(value.serial != .max)"
            }
            let observations = ids.map { id -> String in
                let hardware = candidates.first { $0.displayID == id }
                let matches = expected.flatMap { saved in hardware.map { "\(saved.vendor == $0.vendor)/\(saved.model == $0.model)/\(saved.serial == $0.serial)" } } ?? "unobserved"
                let builtInFlag = CGDisplayIsBuiltin(id)
                let kind = builtInFlag == 1 ? "builtin" : (builtInFlag == 0 ? "external" : "unknown")
                return "{savedID=\(expected?.displayID == id) kind=\(kind) online=\(CGDisplayIsOnline(id) == 1) active=\(CGDisplayIsActive(id) == 1) uuid=\(exactStates[id] ?? "unobserved")/\(fallbackStates[id] ?? "unobserved") fields=\(fields(hardware)) matches=\(matches)}"
            }.joined(separator: " ")
            let matches = expected.map { saved in candidates.filter { saved.matchesHardware($0) }.count } ?? 0
            traceConnectionIdentity("enable=\(enabled) source=\(list.source) count=\(ids.count) known=\(expected != nil) savedFields=\(fields(expected)) savedInList=\(expected.map { ids.contains($0.displayID) } ?? false) eligible=\(candidates.count) matches=\(matches) result=\(result == nil ? "unresolved" : "hardware") \(observations)")
        }
        return result
    }

    private func traceConnectionIdentity(_ event: String) {
        guard event != lastConnectionIdentityTrace else { return }
        lastConnectionIdentityTrace = event
        // Contains flags and counts only, never UUIDs, IDs, serials or names.
        var events = UserDefaults.standard.stringArray(forKey: "connectionIdentityTrace") ?? []
        events.append("\(ISO8601DateFormatter().string(from: Date())) \(event)")
        UserDefaults.standard.set(Array(events.suffix(40)), forKey: "connectionIdentityTrace")
    }

    func brightness(_ id: CGDirectDisplayID) -> Double? {
        guard let get = symbol(displayServices, ["DisplayServicesGetBrightness"], as: GetBrightness.self) else { return nil }
        var value: Float = 0
        guard get(id, &value) == 0, value.isFinite, value >= 0, value <= 1 else { return nil }
        return Double(value)
    }

    func setBrightness(_ id: CGDirectDisplayID, value: Double) throws {
        guard let set = symbol(displayServices, ["DisplayServicesSetBrightness"], as: SetBrightness.self),
              set(id, Float(ControlMath.clamp(value))) == 0 else {
            throw DisplayFailure.message("macOS could not change this display’s hardware brightness.")
        }
    }

    func setConnected(uuid: String, enabled: Bool) throws {
        guard let id = currentID(for: uuid, connectionChange: enabled) else { throw DisplayFailure.notAttached }
        let wakeTarget = enabled ? nil : BuiltInPanelTarget.capture(displayID: id, expectedUUID: uuid)
        guard let set = symbol(skyLight, ["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"], as: SetEnabled.self) else {
            throw DisplayFailure.message("Display connection control is unavailable on this macOS version.")
        }
        let active = displayIDs().filter { CGDisplayIsActive($0) != 0 }
        if !ControlMath.mayDisconnect(isEnabled: !enabled, activeCount: active.count, pending: false) { throw DisplayFailure.message("Keep at least one display connected.") }
        var config: CGDisplayConfigRef?
        let start = CGBeginDisplayConfiguration(&config)
        guard start == .success, let config else { throw DisplayFailure.message("Could not start display configuration (\(start.rawValue)).") }
        let result = set(config, id, enabled)
        guard result == .success else {
            CGCancelDisplayConfiguration(config)
            throw DisplayFailure.message("This connection does not support disconnecting (\(result.rawValue)).")
        }
        let finish = CGCompleteDisplayConfiguration(config, .forSession)
        guard finish == .success else { throw DisplayFailure.message("macOS rejected the connection change (\(finish.rawValue)).") }
        if !enabled {
            panelWakeSessions[uuid] = wakeTarget.map { PanelWakeSession(target: $0) }
            if CGDisplayIsBuiltin(id) == 1 || wakeTarget != nil {
                traceConnectionIdentity("panel wake capture: captured=\(wakeTarget != nil)")
            }
        }
    }

    /// This only wakes the captured kernel panel. A later normal lookup must
    /// identify the CoreGraphics display before any layout transaction is made.
    @discardableResult func wakeBuiltInIfNeeded(uuid: String, completion: @escaping (String) -> Void) -> Bool {
        let owned = (UserDefaults.standard.stringArray(forKey: "ownedDisconnects") ?? []).contains(uuid)
        guard owned, lidClosed == false, var session = panelWakeSessions[uuid],
              session.target.isCurrentlyValid(), let executable = Bundle.main.executableURL,
              session.budget.begin(now: ProcessInfo.processInfo.systemUptime) else {
            traceConnectionIdentity("panel wake skipped: owned=\(owned) captured=\(panelWakeSessions[uuid] != nil)")
            return false
        }
        panelWakeSessions[uuid] = session
        let target = session.target, generation = session.generation
        traceConnectionIdentity("panel wake started: attempt=\(session.budget.attempts)")
        panelWakeQueue.async {
            let result = DDCCommandRunner(helper: executable, timeout: 3).run(
                ["--wake-built-in-panel", String(target.registryEntryID)], acceptingExitCodes: [0, 2, 3, 4, 5, 6, 7])
            let status: String
            switch result {
            case .success(let data):
                let report = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let allowed = ["panel wake: request accepted", "panel wake: invalid arguments",
                    "panel wake: captured internal service unavailable", "panel wake: framework unavailable",
                    "panel wake: required symbols unavailable", "panel wake: lid is closed or unknown",
                    "panel wake: open failed", "panel wake: lid changed or unknown", "panel wake: power request failed"]
                status = allowed.contains(report) ? report : "invalid helper report"
            case .failure(.timedOut): status = "timed out"
            case .failure: status = "rejected"
            }
            DispatchQueue.main.async {
                if self.panelWakeSessions[uuid]?.generation == generation {
                    self.panelWakeSessions[uuid]?.budget.finish()
                    self.traceConnectionIdentity("panel wake completed: \(status)")
                }
                completion(status)
            }
        }
        return true
    }

    func forgetBuiltInWakeTarget(uuid: String) { panelWakeSessions.removeValue(forKey: uuid) }

    func setMode(_ id: CGDirectDisplayID, mode: CGDisplayMode, permanent: Bool = false) throws {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            throw DisplayFailure.message("Could not start resolution change.")
        }
        let result = CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
        guard result == .success else {
            CGCancelDisplayConfiguration(config)
            throw DisplayFailure.message("This resolution is unavailable (\(result.rawValue)).")
        }
        let finish = CGCompleteDisplayConfiguration(config, permanent ? .permanently : .forSession)
        guard finish == .success else { throw DisplayFailure.message("macOS rejected the resolution (\(finish.rawValue)).") }
    }
}

@MainActor final class DimmingWindows {
    private var windows: [String: NSWindow] = [:]
    func set(uuid: String, screen: NSScreen?, fraction: Double) {
        guard fraction < 0.999, let screen else { remove(uuid); return }
        let window: NSWindow
        if let existing = windows[uuid] { window = existing } else {
            window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.backgroundColor = .black; window.isOpaque = false; window.hasShadow = false
            window.ignoresMouseEvents = true; window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            windows[uuid] = window
        }
        window.setFrame(screen.frame, display: true)
        window.alphaValue = 1 - max(0.03, ControlMath.clamp(fraction))
        window.orderFrontRegardless()
    }
    func remove(_ uuid: String) { windows.removeValue(forKey: uuid)?.close() }
    func removeAll() { windows.values.forEach { $0.close() }; windows.removeAll() }
}
