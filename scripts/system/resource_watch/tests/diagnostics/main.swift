import Foundation
import Darwin

var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError(label) }; passed += 1
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("resource-diagnostics-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: root) }
let now = Date()
let iso = ISO8601DateFormatter()
let uid = Int(getuid())
func identity(_ pid: Int, micros: UInt64 = 20, user: Int? = nil) -> ProcessIdentity {
    ProcessIdentity(pid: pid, parentPID: 1, userID: user ?? uid, startSeconds: 1_000, startMicroseconds: micros)
}
func row(_ identity: ProcessIdentity, path: String = "/fixture") -> [String: Any] {
    ["pid": identity.pid, "action_identity": identity.json, "path": path, "cpu_core_percent": 150.0]
}
func incident(_ id: String, _ rows: [[String: Any]], date: Date? = nil) -> [String: Any] {
    ["id": id, "latest": ["time": iso.string(from: date ?? now), "top_processes": rows]]
}
var commands = 0
var hooks = IncidentDiagnosticHooks(now: { now }, currentUID: uid, identity: { identity($0) }, command: { _, _, _, _ in
    commands += 1; fatalError("sample must not run for rejected candidates")
})
let stale = captureIncidentDiagnostics(root: root, incident: incident("stale", [row(identity(101))], date: now.addingTimeInterval(-121)), hooks: hooks)
check(stale["reason"] as? String == "snapshot_expired", "stale snapshot is recorded without executing sample")
let restricted = captureIncidentDiagnostics(root: root, incident: incident("restricted", [row(identity(102, user: 0), path: "/System/WindowServer")]), hooks: hooks)
check((restricted["samples"] as! [[String: Any]])[0]["reason"] as? String == "different_uid_or_system_process_no_privilege_escalation", "system process receives unavailable evidence without sudo")
hooks.identity = { identity($0, micros: 21) }
let reused = captureIncidentDiagnostics(root: root, incident: incident("reused", [row(identity(103))]), hooks: hooks)
check((reused["samples"] as! [[String: Any]])[0]["reason"] as? String == "identity_or_uid_changed", "microsecond PID reuse cannot authorize sampling")
hooks.identity = { identity($0, user: uid + 1) }
let uidChanged = captureIncidentDiagnostics(root: root, incident: incident("uid-changed", [row(identity(103))]), hooks: hooks)
check((uidChanged["samples"] as! [[String: Any]])[0]["reason"] as? String == "identity_or_uid_changed", "same PID/start with changed uid cannot authorize sampling")
hooks.identity = { _ in nil }
let exited = captureIncidentDiagnostics(root: root, incident: incident("exited", [row(identity(104))]), hooks: hooks)
check((exited["samples"] as! [[String: Any]])[0]["reason"] as? String == "process_exited_or_identity_unavailable", "exited process is not sampled")
check(commands == 0, "all rejection cases execute no external command")

let stack = "Sampling process fixture\nCall graph:\n    2000 Thread_fixture\n    + 2000 __workq_kernreturn (in libsystem_kernel.dylib) + 8\nTotal number in stack (recursive counted multiple):\nBinary Images:\n"
hooks.identity = { identity($0) }
hooks.command = { executable, arguments, timeout, limit in
    commands += 1
    check(executable == "/bin/sh" && arguments[2] == "resource-watch-sample", "fixed wrapper has no input interpolation")
    check(arguments[1].contains("ulimit -f") && arguments.suffix(2).first == "-file", "sample file output has its own resource limit")
    check(timeout == 8 && limit == 64 * 1024, "sampling command has bounded time and stdout")
    try! stack.write(toFile: arguments.last!, atomically: true, encoding: .utf8)
    return SamplingCommandResult(output: "done", health: ["succeeded": true])
}
var ghostty = row(identity(105), path: "/Applications/Ghostty.app/Contents/MacOS/ghostty")
ghostty["terminal_protected"] = true
let captured = captureIncidentDiagnostics(root: root, incident: incident("captured", [ghostty, row(identity(106)), row(identity(107))]), hooks: hooks)
check(commands == 2 && captured["attempted_processes"] as? Int == 2, "capture attempts at most two processes, including read-only Ghostty")
let records = captured["samples"] as! [[String: Any]]
check(records.allSatisfy { $0["status"] as? String == "captured" }, "completed samples have paths and successful status")
check((records[0]["summary"] as! [String: Any])["modules_in_excerpt"] as? [String] == ["libsystem_kernel.dylib"], "module evidence is extracted from call graph")
check((records[0]["summary"] as! [String: Any])["interpretation_limit"] as? String != nil, "waiting stack is not called CPU root cause or deadlock")
let repeated = captureIncidentDiagnostics(root: root, incident: incident("captured", [ghostty]), hooks: hooks)
check(commands == 2 && repeated["captured_processes"] as? Int == 2, "same event does not sample again")
check(JSONSerialization.isValidJSONObject(captured), "diagnostic receipt remains valid JSON")
let invalid = captureIncidentDiagnostics(root: root, incident: incident("../escape", [ghostty]), hooks: hooks)
check(invalid["reason"] as? String == "invalid_incident_id" && commands == 2, "incident id cannot escape evidence directory")
let newlineID = captureIncidentDiagnostics(root: root, incident: incident("unsafe\n", [ghostty]), hooks: hooks)
check(newlineID["reason"] as? String == "invalid_incident_id", "incident id must match completely without trailing newline")

hooks.command = { _, _, _, _ in
    commands += 1
    return SamplingCommandResult(output: nil, health: ["succeeded": false, "exit_code": 1])
}
let denied = captureIncidentDiagnostics(root: root, incident: incident("sample-denied", [row(identity(110))]), hooks: hooks)
check((denied["samples"] as! [[String: Any]])[0]["reason"] as? String == "sample_unavailable_or_permission_denied_no_stack", "sample refusal records an honest unavailable reason")
check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("incidents/sample-denied-sample-110.txt").path), "empty refused sample file is removed")

var identityReads = 0
hooks.identity = { pid in identityReads += 1; return identity(pid, micros: identityReads > 1 ? 21 : 20) }
hooks.command = { _, arguments, _, _ in
    commands += 1
    try! stack.write(toFile: arguments.last!, atomically: true, encoding: .utf8)
    return SamplingCommandResult(output: "done", health: ["succeeded": true])
}
let raced = captureIncidentDiagnostics(root: root, incident: incident("race", [row(identity(111))]), hooks: hooks)
check((raced["samples"] as! [[String: Any]])[0]["reason"] as? String == "identity_changed_or_exited_during_sample_discarded", "identity changing during sampling invalidates attribution")
check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("incidents/race-sample-111.txt").path), "raced sample is discarded rather than associated with old process")

hooks.identity = { identity($0) }
hooks.command = { _, arguments, _, _ in
    commands += 1
    try! Data(repeating: 65, count: 2 * 1024 * 1024).write(to: URL(fileURLWithPath: arguments.last!))
    return SamplingCommandResult(output: nil, health: ["succeeded": false, "timed_out": true])
}
let overflow = captureIncidentDiagnostics(root: root, incident: incident("overflow", [row(identity(112)), row(identity(113))]), hooks: hooks)
let overflowSamples = overflow["samples"] as! [[String: Any]]
check(overflowSamples.allSatisfy { $0["file_truncated"] as? Bool == true && $0["status"] as? String == "partial" }, "oversized/incomplete samples are explicitly partial")
check(overflow["sample_bytes"] as? Int == 2 * 1024 * 1024, "even an oversized writer cannot leave more than two MiB of samples")
let overflowFiles = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("incidents"), includingPropertiesForKeys: [.fileSizeKey]).filter { $0.lastPathComponent.hasPrefix("overflow-") }
let totalSize = try overflowFiles.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
check(totalSize <= 4 * 1024 * 1024, "persisted receipt plus sample files fits event budget")

// Real smoke test owns its target and only samples it; no user process is touched.
let target = Process(); target.executableURL = URL(fileURLWithPath: "/bin/sleep"); target.arguments = ["20"]
try target.run()
defer { if target.isRunning { target.terminate() }; target.waitUntilExit() }
let targetIdentity = processIdentity(Int(target.processIdentifier))!
let actual = captureIncidentDiagnostics(root: root, incident: incident("owned-live", [row(targetIdentity, path: "/bin/sleep")], date: Date()))
let actualSamples = actual["samples"] as! [[String: Any]]
check(actual["attempted_processes"] as? Int == 1, "real fixture goes through bounded sample command")
check(target.isRunning && processIdentity(Int(target.processIdentifier)).map { targetIdentity.sameInstance(as: $0) } == true, "read-only sampling leaves owned fixture running with same identity")
check(actualSamples.first?["status"] as? String == "captured", "real same-UID fixture sample succeeds")
let savedURL = root.appendingPathComponent("incidents/owned-live-diagnostics.json")
check(FileManager.default.fileExists(atPath: savedURL.path), "real diagnostics receipt is persisted")
check((actual["sample_bytes"] as? Int ?? Int.max) < 4 * 1024 * 1024, "event evidence remains below size budget")
print("PASS: \(passed) additional diagnostics checks")
