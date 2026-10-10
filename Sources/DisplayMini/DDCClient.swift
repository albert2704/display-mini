import Foundation
import Darwin
import DisplayCore

enum DDCFailure: Error, LocalizedError, Equatable {
    case missingHelper, launchFailed, timedOut, oversizedOutput, commandFailed, invalidResponse, unconfirmedWrite
    var errorDescription: String? {
        switch self {
        case .missingHelper: return "The monitor helper is missing. Rebuild or reinstall the app."
        case .launchFailed: return "The monitor helper could not start. Rebuild or reinstall the app."
        case .timedOut: return "The monitor check timed out. Check DDC/CI and try a direct connection."
        case .oversizedOutput: return "The monitor helper returned too much data. Rebuild or reinstall the app."
        case .commandFailed: return "The helper could not find or communicate with this display. Refresh displays and check the cable."
        case .invalidResponse: return "The helper returned an invalid or mismatched display report. Detect again or reinstall the app."
        case .unconfirmedWrite: return "The monitor did not confirm the change. Refresh or detect its controls again."
        }
    }
}

/// Uses a nonblocking pipe so both output collection and cleanup have a deadline.
struct DDCCommandRunner {
    let helper: URL
    var timeout: TimeInterval = 3
    func run(_ arguments: [String]) -> Result<Data, DDCFailure> {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return .failure(.missingHelper) }
        let process = Process(), pipe = Pipe(), finished = DispatchSemaphore(value: 0)
        process.executableURL = helper; process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return .failure(.launchFailed) }
        pipe.fileHandleForWriting.closeFile()
        defer { pipe.fileHandleForReading.closeFile() }
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        func stop() {
            guard process.isRunning else { return }
            process.terminate()
            if finished.wait(timeout: .now() + 0.2) == .timedOut && process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.3)
            }
        }
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            stop(); return .failure(.invalidResponse)
        }
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(0, timeout) * 1_000_000_000)
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        var exited = false, eof = false
        while DispatchTime.now().uptimeNanoseconds < deadline {
            // One read per iteration also bounds an endlessly writing helper.
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                guard data.count + count <= 65536 else { stop(); return .failure(.oversizedOutput) }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 { eof = true }
            else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                stop(); return .failure(.invalidResponse)
            }
            if !exited { exited = finished.wait(timeout: .now()) == .success }
            if exited && eof {
                return process.terminationStatus == 0 ? .success(data) : .failure(.commandFailed)
            }
            if count <= 0 {
                var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
                _ = poll(&pollDescriptor, 1, 10)
                // A closed pipe can precede process exit; avoid spinning on HUP.
                if eof && !exited { exited = finished.wait(timeout: .now() + 0.01) == .success }
            }
        }
        stop()
        return .failure(.timedOut)
    }
}

final class DDCClient {
    private let queue = DispatchQueue(label: "dev.albert.DisplayMini.ddc", qos: .userInitiated)
    private let runner: DDCCommandRunner
    init(helper: URL? = nil) {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/m1ddc")
        let fallback = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Vendor/m1ddc")
        runner = DDCCommandRunner(helper: helper ?? (FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : fallback))
    }

    func read(uuid: String, timing: DDCTiming, completion: @escaping (Result<DDCProbe, DDCFailure>) -> Void) {
        queue.async {
            let result = self.runner.run(["--delay-ms", String(timing.delayMS), "display", uuid, "probe"]).flatMap { data -> Result<DDCProbe, DDCFailure> in
                guard let probe = DDCProbe.parse(data, expectedUUID: uuid, timing: timing) else { return .failure(.invalidResponse) }
                return .success(probe)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func write(uuid: String, timing: DDCTiming, attribute: String, value: Int, completion: @escaping (Result<Void, DDCFailure>) -> Void) {
        queue.async {
            let prefix = ["--delay-ms", String(timing.delayMS), "display", uuid]
            let result = self.runner.run(prefix + ["set", attribute, String(value)])
            var verified = result.map { _ in () }
            if case .success = result {
                let readback = self.runner.run(prefix + ["get", attribute])
                if case .success(let data) = readback, let output = String(data: data, encoding: .utf8), ControlMath.parseDDC(output) == value {
                    verified = .success(())
                } else { verified = .failure(.unconfirmedWrite) }
            }
            DispatchQueue.main.async { completion(verified) }
        }
    }

    func readAdvanced(uuid: String, timing: DDCTiming, completion: @escaping (Result<AdvancedDDCProbe, DDCFailure>) -> Void) {
        queue.async {
            let result = self.runner.run(["--delay-ms", String(timing.delayMS), "display", uuid, "probe-advanced"]).flatMap { data -> Result<AdvancedDDCProbe, DDCFailure> in
                guard let probe = AdvancedDDCProbe.parse(data, expectedUUID: uuid, timing: timing) else { return .failure(.invalidResponse) }
                return .success(probe)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Input switching can remove the DDC link. Success means command delivery only.
    func sendInput(uuid: String, timing: DDCTiming, input: MonitorInput, completion: @escaping (Result<Void, DDCFailure>) -> Void) {
        queue.async {
            let result = self.runner.run(["--delay-ms", String(timing.delayMS), "display", uuid, "set", "input", String(input.rawValue)]).map { _ in () }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
