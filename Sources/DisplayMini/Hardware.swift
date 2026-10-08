import AppKit
import CoreGraphics
import Darwin
import DisplayCore

enum DisplayFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
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

    private func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ names: [String], as: T.Type) -> T? {
        guard let handle else { return nil }
        for name in names { if let pointer = dlsym(handle, name) { return unsafeBitCast(pointer, to: T.self) } }
        return nil
    }

    var canConnect: Bool { symbol(skyLight, ["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"], as: SetEnabled.self) != nil }

    func displayIDs() -> [CGDirectDisplayID] {
        var ids = [UInt32](repeating: 0, count: 64), count: UInt32 = 0
        if let list = symbol(skyLight, ["SLSGetDisplayList", "CGSGetDisplayList"], as: GetList.self),
           list(64, &ids, &count) == .success { return Array(ids.prefix(Int(min(count, 64)))) }
        guard CGGetOnlineDisplayList(64, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(min(count, 64))))
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
        let ids = displayIDs()
        if let exact = ids.first(where: { rawUUID($0) == uuid }) { return exact }
        guard let expected = knownIdentities[uuid] else { return nil }
        return DisplayIdentity.resolve(expected, among: ids.filter { rawUUID($0) == nil }.map(identity))
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
        guard let id = currentID(for: uuid) else { throw DisplayFailure.message("Display is no longer attached.") }
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
    }

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

struct DDCReading {
    var brightness: Double?
    var brightnessMaximum = 100
    var volume: Double?
    var volumeMaximum = 100
    var detail: String?
}

final class DDCClient {
    private let queue = DispatchQueue(label: "dev.albert.DisplayMini.ddc", qos: .userInitiated)
    private let helper: URL
    init() {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/m1ddc")
        helper = FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled :
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Vendor/m1ddc")
    }

    private func run(_ arguments: [String]) -> Result<String, Error> {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            return .failure(DisplayFailure.message("Monitor helper is missing. Rebuild the app with scripts/build.sh."))
        }
        let process = Process(), pipe = Pipe(), finished = DispatchSemaphore(value: 0)
        process.executableURL = helper; process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return .failure(error) }
        if finished.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 0.3) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            return .failure(DisplayFailure.message("The monitor did not respond. Check DDC/CI in its on-screen menu and the cable."))
        }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            return .failure(DisplayFailure.message(output.isEmpty ? "The monitor rejected the DDC command." : output))
        }
        return .success(output)
    }

    func read(uuid: String, completion: @escaping (DDCReading) -> Void) {
        queue.async {
            var reading = DDCReading()
            for attribute in ["luminance", "volume"] {
                let value = self.run(["display", uuid, "get", attribute])
                if case .success(let output) = value, let current = ControlMath.parseDDC(output) {
                    let maxResult = self.run(["display", uuid, "max", attribute])
                    // A successful current read alone cannot establish a safe scaling range.
                    guard case .success(let maxOutput) = maxResult,
                          let maximum = ControlMath.parseDDC(maxOutput), maximum > 0, current <= maximum else {
                        reading.detail = "The monitor did not report a valid control range. Retry DDC detection."
                        continue
                    }
                    if attribute == "luminance" { reading.brightness = Double(current) / Double(maximum); reading.brightnessMaximum = maximum }
                    else { reading.volume = Double(current) / Double(maximum); reading.volumeMaximum = maximum }
                } else if case .failure(let error) = value { reading.detail = error.localizedDescription }
                else { reading.detail = "The monitor returned an unsupported DDC value." }
            }
            DispatchQueue.main.async { completion(reading) }
        }
    }

    func write(uuid: String, attribute: String, value: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result = self.run(["display", uuid, "set", attribute, String(value)])
            var verified = result.map { _ in () }
            if case .success = result {
                let readback = self.run(["display", uuid, "get", attribute])
                if case .success(let output) = readback, ControlMath.parseDDC(output) == value { verified = .success(()) }
                else { verified = .failure(DisplayFailure.message("The monitor did not confirm the change. Refresh or detect its controls again.")) }
            }
            DispatchQueue.main.async { completion(verified) }
        }
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
