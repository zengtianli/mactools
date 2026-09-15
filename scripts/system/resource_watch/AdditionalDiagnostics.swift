import Foundation
import Darwin

// Called by the monitor's short-lived --capture child, never on its sampling loop.
// Dependencies are injectable so identity/permission failures can be tested without
// launching sample or touching a user process.
struct IncidentDiagnosticHooks {
    var now: () -> Date = { Date() }
    var currentUID: Int = Int(getuid())
    var identity: (Int) -> ProcessIdentity? = processIdentity
    var command: (String, [String], Double, Int) -> SamplingCommandResult = {
        samplingCommand($0, $1, timeout: $2, outputLimit: $3)
    }
}

private let diagnosticSampleLimit = 1024 * 1024
private let diagnosticOutputLimit = 64 * 1024

private func diagnosticSave(_ value: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    // Two <=1 MiB samples plus this <=256 KiB receipt remain below 4 MiB/event.
    guard data.count <= 256 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

private func diagnosticTimestamp(_ value: Any?) -> Date? {
    guard let text = value as? String else { return nil }
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions.insert(.withFractionalSeconds)
    return formatter.date(from: text)
}

private func diagnosticIdentity(_ row: [String: Any]) -> ProcessIdentity? {
    guard let value = row["action_identity"] as? [String: Any],
          let pid = value["pid"] as? Int, pid > 0, pid <= Int(Int32.max),
          pid == row["pid"] as? Int,
          let parent = value["ppid"] as? Int,
          let uid = value["uid"] as? Int, uid >= 0,
          let seconds = value["start_seconds"] as? NSNumber, seconds.doubleValue > 0,
          let micros = value["start_microseconds"] as? NSNumber,
          micros.doubleValue >= 0, micros.doubleValue < 1_000_000 else { return nil }
    return ProcessIdentity(pid: pid, parentPID: parent, userID: uid,
                           startSeconds: seconds.uint64Value, startMicroseconds: micros.uint64Value)
}

func incidentStackSummary(_ text: String) -> [String: Any] {
    var excerpt: [String] = []
    var inGraph = false
    for line in text.components(separatedBy: .newlines) {
        if line.hasPrefix("Call graph:") { inGraph = true; continue }
        if inGraph && (line.hasPrefix("Total number in stack") || line.hasPrefix("Binary Images:")) { break }
        guard inGraph, !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
        excerpt.append(String(line.prefix(240)))
        if excerpt.count == 16 { break }
    }
    let expression = try? NSRegularExpression(pattern: #"\(in ([^)]+)\)"#)
    var modules: [String] = []
    for line in excerpt {
        for match in expression?.matches(in: line, range: NSRange(line.startIndex..., in: line)) ?? [] {
            if let range = Range(match.range(at: 1), in: line) {
                let name = String(line[range].prefix(100))
                if !modules.contains(name) { modules.append(name) }
            }
        }
    }
    let observed = modules.isEmpty ? "采样未提取到可命名模块，保留原始文本供核查。" :
        "2 秒栈采样前段出现模块：" + modules.prefix(8).joined(separator: "、") + "。"
    return ["observation": observed, "modules_in_excerpt": Array(modules.prefix(8)),
            "stack_excerpt": excerpt,
            "interpretation_limit": "sample 包含运行及等待线程；栈出现次数不等于 CPU 热点。单次栈只能提供调用位置线索，不能据此认定死进程、死锁或根因。应结合本事件 CPU 差分、任务进展及调整后的复测。"]
}

func captureIncidentDiagnostics(root: URL, incident: [String: Any]) -> [String: Any] {
    captureIncidentDiagnostics(root: root, incident: incident, hooks: IncidentDiagnosticHooks())
}

func captureIncidentDiagnostics(root: URL, incident: [String: Any], hooks: IncidentDiagnosticHooks) -> [String: Any] {
    let began = ProcessInfo.processInfo.systemUptime
    let now = hooks.now()
    let formatter = ISO8601DateFormatter()
    var report: [String: Any] = ["schema_version": 1, "status": "unavailable",
        "captured_at": formatter.string(from: now), "read_only": true, "local_only": true,
        "max_sampled_processes": 2, "timeout_seconds_per_process": 8,
        "retained_bytes_limit": 4 * 1024 * 1024, "samples": [[String: Any]](),
        "note": "仅采集当前用户进程的调用栈；不暂停、结束或修改目标进程，不使用 sudo。"]
    guard let id = incident["id"] as? String,
          id.range(of: #"\A[A-Za-z0-9][A-Za-z0-9_-]{0,99}\z"#, options: .regularExpression) != nil else {
        report["reason"] = "invalid_incident_id"; return report
    }
    report["incident_id"] = id
    let directory = root.appendingPathComponent("incidents", isDirectory: true)
    let receipt = directory.appendingPathComponent(id + "-diagnostics.json")
    report["diagnostics_path"] = receipt.path
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        if let file = try? FileHandle(forReadingFrom: receipt) {
            defer { try? file.close() }
            let existing = try file.read(upToCount: 256 * 1024 + 1) ?? Data()
            // One capture attempt per incident. A crashed attempt is evidence, not
            // permission for repeated sampling during the same high-load event.
            if existing.count <= 256 * 1024,
               let saved = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any],
               saved["incident_id"] as? String == id { return saved }
            report["reason"] = "existing_receipt_unreadable"; return report
        }
        let fd = open(receipt.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { report["reason"] = "receipt_already_exists_or_unwritable"; return report }
        close(fd)
    } catch { report["reason"] = "evidence_directory_unavailable"; report["error"] = String(describing: error); return report }

    func finish(_ status: String, reason: String? = nil) -> [String: Any] {
        report["status"] = status
        if let reason = reason { report["reason"] = reason }
        report["duration_seconds"] = ProcessInfo.processInfo.systemUptime - began
        do { try diagnosticSave(report, to: receipt) }
        catch { report["receipt_write_error"] = String(describing: error); report["status"] = "write_failed" }
        return report
    }
    let snapshot = incident["latest"] as? [String: Any] ?? [:]
    guard let sampledAt = diagnosticTimestamp(snapshot["time"]) else { return finish("skipped", reason: "snapshot_time_missing_or_invalid") }
    let age = now.timeIntervalSince(sampledAt)
    report["snapshot_time"] = formatter.string(from: sampledAt); report["snapshot_age_seconds"] = age
    guard age >= -5 && age <= 120 else { return finish("skipped", reason: age > 120 ? "snapshot_expired" : "snapshot_from_future") }
    report["status"] = "capturing"
    do { try diagnosticSave(report, to: receipt) }
    catch { return finish("write_failed", reason: "initial_receipt_write_failed") }

    let rows = Array((snapshot["top_processes"] as? [[String: Any]] ?? []).prefix(15))
    var samples: [[String: Any]] = []
    var attempted = 0; var captured = 0; var seen: Set<Int> = []
    var retainedBytes = 0
    for row in rows {
        guard attempted < 2 else { break }
        let pid = row["pid"] as? Int ?? 0
        guard !seen.contains(pid) else { continue }; seen.insert(pid)
        var result: [String: Any] = ["pid": pid, "path": String((row["path"] as? String ?? "").prefix(2048)),
            "status": "unavailable", "cpu_core_percent": row["cpu_core_percent"] as? NSNumber ?? NSNull(),
            "terminal_protected": row["terminal_protected"] as? Bool ?? false]
        func skipped(_ reason: String) { result["reason"] = reason; samples.append(result) }
        guard let expected = diagnosticIdentity(row) else { skipped("missing_or_invalid_snapshot_identity"); continue }
        result["snapshot_identity"] = expected.json
        guard expected.userID == hooks.currentUID && expected.userID != 0 else { skipped("different_uid_or_system_process_no_privilege_escalation"); continue }
        guard row["is_zombie"] as? Bool != true && !(row["stat"] as? String ?? "").contains("Z") else { skipped("zombie_has_no_executing_stack"); continue }
        guard let live = hooks.identity(pid) else { skipped("process_exited_or_identity_unavailable"); continue }
        result["verified_identity"] = live.json
        guard live.sameInstance(as: expected) && live.userID == expected.userID else { skipped("identity_or_uid_changed"); continue }
        guard hooks.now().timeIntervalSince(sampledAt) <= 120 else { skipped("snapshot_expired_before_sample"); continue }

        let sampleURL = directory.appendingPathComponent("\(id)-sample-\(pid).txt")
        let fd = open(sampleURL.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { skipped("sample_path_already_exists_or_unwritable"); continue }; close(fd)
        attempted += 1
        let started = ProcessInfo.processInfo.systemUptime
        // sample -file bypasses stdout limits. This fixed argv-only shell wrapper
        // caps the child's regular files too (ulimit units are <=1024 bytes here).
        // exec preserves samplingCommand's owned child/group cleanup boundary.
        let command = hooks.command("/bin/sh", ["-c", "ulimit -f 1024 || exit 125; exec /usr/bin/sample \"$@\"",
            "resource-watch-sample", String(pid), "2", "-file", sampleURL.path], 8, diagnosticOutputLimit)
        result["duration_seconds"] = ProcessInfo.processInfo.systemUptime - started
        result["command_health"] = command.health
        let after = hooks.identity(pid)
        if let after = after { result["identity_after_sample"] = after.json }
        guard let after = after, after.sameInstance(as: expected), after.userID == expected.userID else {
            try? FileManager.default.removeItem(at: sampleURL)
            skipped("identity_changed_or_exited_during_sample_discarded"); continue
        }
        do {
            let file = try FileHandle(forReadingFrom: sampleURL); defer { try? file.close() }
            let bytes = try file.read(upToCount: diagnosticSampleLimit + 1) ?? Data()
            let kept = Data(bytes.prefix(diagnosticSampleLimit))
            if bytes.count > diagnosticSampleLimit {
                try kept.write(to: sampleURL, options: .atomic)
                result["file_truncated"] = true
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sampleURL.path)
            let text = String(decoding: kept, as: UTF8.self)
            guard !kept.isEmpty else {
                try? FileManager.default.removeItem(at: sampleURL)
                let timedOut = command.health["timed_out"] as? Bool == true
                skipped(timedOut ? "sample_timed_out_no_stack" : "sample_unavailable_or_permission_denied_no_stack"); continue
            }
            result["sample_path"] = sampleURL.path; result["sample_bytes"] = kept.count
            retainedBytes += kept.count
            result["summary"] = incidentStackSummary(text)
            let succeeded = command.health["succeeded"] as? Bool == true
            result["status"] = succeeded && bytes.count <= diagnosticSampleLimit ? "captured" : "partial"
            if !succeeded { result["reason"] = "sample_incomplete_see_command_health" }
            captured += 1; samples.append(result)
        } catch {
            try? FileManager.default.removeItem(at: sampleURL)
            result["error"] = String(describing: error); skipped("sample_file_unavailable")
        }
    }
    report["samples"] = samples; report["attempted_processes"] = attempted
    report["captured_processes"] = captured; report["sample_bytes"] = retainedBytes
    report["candidate_scope"] = "snapshot top_processes first 15, in recorded CPU order; at most 2 same-UID instances attempted"
    return finish(captured > 0 ? "captured" : "unavailable", reason: rows.isEmpty ? "no_top_processes" : nil)
}
