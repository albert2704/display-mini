import Foundation
import DisplayCore

@main struct ProcessTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func helper(_ name: String, _ body: String) throws -> URL {
            let path = root.appendingPathComponent(name)
            try ("#!/bin/bash\n" + body + "\n").write(to: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
            return path
        }
        let success = try helper("success", "printf '75\\n'")
        let successResult = try DDCCommandRunner(helper: success).run([]).get()
        precondition(String(data: successResult, encoding: .utf8) == "75\n")
        let missing = DDCCommandRunner(helper: root.appendingPathComponent("missing")).run([])
        if case .failure(.missingHelper) = missing {} else { preconditionFailure("Missing helper was not diagnosed") }
        let reject = try helper("reject", "exit 4")
        if case .failure(.commandFailed) = DDCCommandRunner(helper: reject).run([]) {} else { preconditionFailure("Exit status was ignored") }
        // Bash builtins flood the pipe without leaving a child holding its descriptors.
        let noisy = try helper("noisy", "for ((i=0;i<9000;i++)); do printf '0123456789'; done")
        if case .failure(.oversizedOutput) = DDCCommandRunner(helper: noisy).run([]) {} else { preconditionFailure("Output was not bounded") }
        let hanging = try helper("hanging", "exec /bin/sleep 10")
        let start = Date()
        if case .failure(.timedOut) = DDCCommandRunner(helper: hanging, timeout: 0.1).run([]) {} else { preconditionFailure("Timeout did not fire") }
        precondition(Date().timeIntervalSince(start) < 2)
        // A descendant inherits stdout after its parent exits. Collection must
        // close its descriptor at the deadline without leaving a drain worker.
        let inherited = try helper("inherited", "/bin/sleep 1 &\nexit 0")
        let inheritedStart = Date()
        if case .failure(.timedOut) = DDCCommandRunner(helper: inherited, timeout: 0.1).run([]) {} else { preconditionFailure("Inherited pipe was not bounded") }
        precondition(Date().timeIntervalSince(inheritedStart) < 0.8)
        let commandLog = root.appendingPathComponent("commands").path
        let routed = try helper("routed", """
        printf '%s:%s\\n' "$5" "$6" >> '\(commandLog)'
        case "$5:$6" in
          set:input) printf 'Writing 15\\n' ;;
          get:input) exit 9 ;;
          set:contrast) printf 'Writing 80\\n' ;;
          get:contrast) printf '80\\n' ;;
          set:volume) printf 'Writing 30\\n' ;;
          get:volume) printf '29\\n' ;;
          *) exit 8 ;;
        esac
        """)
        let client = DDCClient(helper: routed)
        let inputResult: Result<Void, DDCFailure> = await withCheckedContinuation { continuation in
            client.sendInput(uuid: "00000000-0000-4000-8000-00000000A001", timing: .standard, input: .displayPort1) { continuation.resume(returning: $0) }
        }
        try inputResult.get()
        let contrastResult: Result<Void, DDCFailure> = await withCheckedContinuation { continuation in
            client.write(uuid: "00000000-0000-4000-8000-00000000A001", timing: .standard, attribute: "contrast", value: 80) { continuation.resume(returning: $0) }
        }
        try contrastResult.get()
        let mismatch: Result<Void, DDCFailure> = await withCheckedContinuation { continuation in
            client.write(uuid: "00000000-0000-4000-8000-00000000A001", timing: .standard, attribute: "volume", value: 30) { continuation.resume(returning: $0) }
        }
        if case .failure(.unconfirmedWrite) = mismatch {} else { preconditionFailure("Mismatched readback accepted") }
        let commands = try String(contentsOfFile: commandLog, encoding: .utf8)
        precondition(commands == "set:input\nset:contrast\nget:contrast\nset:volume\nget:volume\n")
        print("Passed 6 helper process scenarios (success, missing, rejection, excessive output, timeout, inherited pipe).")
        print("Passed input delivery without readback, verified contrast, and mismatched readback checks.")
    }
}
