import Foundation
import DisplayCore

@main struct ProcessTests {
    static func main() throws {
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
        print("Passed 6 helper process scenarios (success, missing, rejection, excessive output, timeout, inherited pipe).")
    }
}
