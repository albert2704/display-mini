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

private final class DDCOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var overflow = false
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        let remaining = max(0, 65536 - data.count)
        if chunk.count > remaining { overflow = true }
        data.append(chunk.prefix(remaining))
    }
    func result() -> Result<Data, DDCFailure> {
        lock.lock(); defer { lock.unlock() }
        return overflow ? .failure(.oversizedOutput) : .success(data)
    }
}

/// Drains while running so a full pipe cannot block process termination.
struct DDCCommandRunner {
    let helper: URL
    var timeout: TimeInterval = 3
    func run(_ arguments: [String]) -> Result<Data, DDCFailure> {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return .failure(.missingHelper) }
        let process = Process(), pipe = Pipe()
        let finished = DispatchSemaphore(value: 0), drained = DispatchSemaphore(value: 0)
        let output = DDCOutputBuffer()
        process.executableURL = helper; process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return .failure(.launchFailed) }
        pipe.fileHandleForWriting.closeFile()
        DispatchQueue.global(qos: .utility).async {
            defer { try? pipe.fileHandleForReading.close(); drained.signal() }
            while let chunk = try? pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                output.append(chunk)
            }
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 0.2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.3)
            }
            _ = drained.wait(timeout: .now() + 0.2)
            return .failure(.timedOut)
        }
        guard drained.wait(timeout: .now() + 0.3) == .success else { return .failure(.timedOut) }
        if case .failure(let failure) = output.result() { return .failure(failure) }
        guard process.terminationStatus == 0 else { return .failure(.commandFailed) }
        return output.result()
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
}
