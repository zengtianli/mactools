import Cocoa
import Darwin

let buildVersion = "2026-09-15-incidents-v2"
let args = CommandLine.arguments
func argument(_ name: String) -> String? { guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }; return args[i + 1] }
let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ResourceWatch")
let iso = ISO8601DateFormatter()
func logError(_ message: String) { FileHandle.standardError.write(Data("\(iso.string(from: Date())) \(message)\n".utf8)) }
func writeJSON(_ value: Any, _ name: String) { do { try IncidentStore.save(value, to: root.appendingPathComponent(name)) } catch { logError("write \(name): \(error)") } }
func append(_ value: [String: Any], _ name: String) {
    do {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]); data.append(10)
        let url = root.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        let file = try FileHandle(forWritingTo: url); defer { try? file.close() }
        guard flock(file.fileDescriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { flock(file.fileDescriptor, LOCK_UN) }
        try file.seekToEnd(); try file.write(contentsOf: data)
    } catch { logError("append \(name): \(error)") }
}
func eventLog(_ event: String, _ fields: [String: Any] = [:]) {
    var value = fields; value["event"] = event; value["time"] = iso.string(from: Date()); value["build_version"] = buildVersion
    append(value, "actions.jsonl")
}
func cpuTicks() -> [UInt32]? {
    var info = host_cpu_load_info(); var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
    guard result == KERN_SUCCESS else { return nil }; return [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
}
func pressure() -> Int { var value: Int32 = 0; var size = MemoryLayout<Int32>.size; return sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 ? Int(value) : 0 }
func hostCPU(_ old: [UInt32], _ ticks: [UInt32]) -> Double? {
    let deltas = zip(ticks, old).map { Double($0 &- $1) }; let total = deltas.reduce(0, +)
    return total > 0 ? 100 * (1 - deltas[2] / total) : nil
}
if args.contains("--version") { print(buildVersion); exit(0) }
if args.contains("--diagnose") {
    let argument = argument("--diagnose") ?? "2"
    guard let seconds = Double(argument), seconds.isFinite, (1...60).contains(seconds) else { logError("--diagnose expects 1–60 seconds"); exit(2) }
    let telemetry = SystemTelemetrySampler(); _ = telemetry.sample()
    let oldProcesses = collectProcesses(); let oldTicks = cpuTicks(); let began = ProcessInfo.processInfo.systemUptime
    Thread.sleep(forTimeInterval: seconds)
    let current = collectProcesses(); let ticks = cpuTicks()
    var snapshot = processReport(previous: oldProcesses, current: current, logicalCores: ProcessInfo.processInfo.activeProcessorCount)
    snapshot.merge(telemetry.sample()) { _, new in new }
    snapshot["time"] = iso.string(from: Date()); snapshot["read_only"] = true; snapshot["build_version"] = buildVersion
    snapshot["logical_cores"] = ProcessInfo.processInfo.activeProcessorCount; snapshot["host_sample_seconds"] = ProcessInfo.processInfo.systemUptime - began
    snapshot["memory_pressure"] = pressure(); snapshot["cpu_percent"] = oldTicks.flatMap { old in ticks.flatMap { hostCPU(old, $0) } } as Any? ?? NSNull()
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys, .prettyPrinted])); print("")
    exit(oldProcesses.collected && current.collected && current.jobsCollected ? 0 : 3)
}

try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
if args.contains("--capture") {
    guard let path = argument("--event-file"), let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let incident = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { eventLog("diagnostics_input_failed"); exit(2) }
    let result = captureIncidentDiagnostics(root: root, incident: incident)
    eventLog("diagnostics_completed", ["incident_id": incident["id"] ?? "", "status": result["status"] ?? "unknown"])
    exit(result["status"] as? String == "write_failed" ? 3 : 0)
}
if args.contains("--prompt") || args.contains("--preview") {
    let preview = args.contains("--preview")
    let source = argument("--event-file").map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent("latest-advice.json")
    guard let data = try? Data(contentsOf: source), let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        eventLog("prompt_load_failed", ["prompt_id": argument("--prompt-id") ?? "", "preview": preview]); exit(2)
    }
    let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching()
    let previewTimeout = Double(argument("--preview-timeout") ?? "120") ?? 120
    let prompt = ResourcePrompt(root: root, promptID: argument("--prompt-id") ?? UUID().uuidString, event: event, preview: preview, timeout: preview ? max(5, min(120, previewTimeout)) : 120) { append($0, "actions.jsonl") }
    prompt.show(); app.run(); exit(0)
}

let once = args.contains("--once")
let lockFD = open(root.appendingPathComponent("monitor.lock").path, O_CREAT | O_RDWR, 0o600)
if !once && (lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0) { exit(0) }
let defaults: [String: Any] = ["interval_seconds": 15, "cpu_threshold": 90, "sustained_seconds": 60, "cooldown_seconds": 1800, "retention_days": 14, "incident_retention_days": 90]
let configURL = root.appendingPathComponent("config.json")
if !FileManager.default.fileExists(atPath: configURL.path) { writeJSON(defaults, "config.json") }
var config = (try? JSONSerialization.jsonObject(with: Data(contentsOf: configURL))) as? [String: Any] ?? defaults
if let data = try? Data(contentsOf: root.appendingPathComponent("alert-state.json")), let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
    config["last_prompt_at"] = saved["last_presented_at"]; config["last_prompt_severity"] = saved["severity"] ?? "warning"
}
func number(_ key: String) -> Double { let value = (config[key] as? NSNumber)?.doubleValue ?? (defaults[key] as? NSNumber)?.doubleValue ?? 0; return value.isFinite ? value : (defaults[key] as? NSNumber)?.doubleValue ?? 0 }
let policy = IncidentPolicy(config: config)
let telemetry = SystemTelemetrySampler(); _ = telemetry.sample()
let store = try IncidentStore(directory: root.appendingPathComponent("incidents"), recoverInterrupted: !once)
var previousProcesses = collectProcesses(); var previous = cpuTicks(); var previousUptime = ProcessInfo.processInfo.systemUptime
var lastDay = ""; var promptTask: Process?; var promptID: String?; var promptStarted = 0.0; var promptAcknowledged = false
var lastAdvice: [String: Any] = [:]; var menu: ResourceMenu?; var lastFailureLog = 0.0
var promptIdentity: ProcessIdentity?
var captureTask: Process?
func launchCapture(_ incident: [String: Any]) {
    guard captureTask?.isRunning != true, let id = incident["id"] as? String else {
        eventLog("diagnostics_skipped_busy"); return
    }
    let task = Process(); task.executableURL = URL(fileURLWithPath: args[0])
    task.arguments = ["--capture", "--event-file", root.appendingPathComponent("incidents/\(id).json").path]
    do { try task.run(); captureTask = task; eventLog("diagnostics_started", ["incident_id": id]) }
    catch { eventLog("diagnostics_launch_failed", ["incident_id": id, "error": String(describing: error)]) }
}
var promptSeverity = "warning"
func launchPrompt(manual: Bool = false) {
    guard !once, promptTask?.isRunning != true, !lastAdvice.isEmpty else {
        if !manual { policy.promptFailed(at: Date().timeIntervalSince1970) }
        return
    }
    let id = UUID().uuidString.lowercased(); let task = Process()
    let input = root.appendingPathComponent("prompt-input.json")
    do { try IncidentStore.save(lastAdvice, to: input) }
    catch { policy.promptFailed(at: Date().timeIntervalSince1970); eventLog("prompt_input_failed", ["error": String(describing: error)]); return }
    promptSeverity = lastAdvice["severity"] as? String ?? "warning"
    task.executableURL = URL(fileURLWithPath: args[0]); task.arguments = ["--prompt", "--prompt-id", id, "--event-file", input.path]
    promptStarted = Date().timeIntervalSince1970; promptAcknowledged = false; promptID = id
    do { try task.run(); promptTask = task; promptIdentity = processIdentity(Int(task.processIdentifier)); eventLog("prompt_launched", ["prompt_id": id, "incident_id": lastAdvice["id"] ?? "", "manual": manual]) }
    catch { policy.promptFailed(at: promptStarted); promptID = nil; eventLog("prompt_launch_failed", ["error": String(describing: error), "prompt_id": id]) }
}
func checkPrompt(_ now: Double) {
    guard let id = promptID else { return }
    if let data = try? Data(contentsOf: root.appendingPathComponent("prompt-state.json")), let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], record["prompt_id"] as? String == id,
       ["prompt_presented", "cancelled", "timed_out", "actions_confirmed", "action_result", "actions_completed"].contains(record["event"] as? String ?? ""), !promptAcknowledged {
        promptAcknowledged = true; policy.promptPresented(at: now, severity: promptSeverity)
        writeJSON(["last_presented_at": now, "prompt_id": id, "severity": promptSeverity], "alert-state.json")
    }
    if promptTask?.isRunning != true {
        if !promptAcknowledged { policy.promptFailed(at: now); eventLog("prompt_exited_before_presented", ["prompt_id": id]) }
        promptID = nil; promptTask = nil; promptIdentity = nil
    } else if !promptAcknowledged && now - promptStarted >= 30 {
        if let identity = promptIdentity, let live = processIdentity(identity.pid), identity.sameInstance(as: live), live.userID == Int(getuid()) {
            promptTask?.terminate()
            eventLog("owned_prompt_timeout_cleanup", ["prompt_id": id, "note": "Only the monitor-created unpresented child receives TERM"])
        } else { eventLog("owned_prompt_cleanup_skipped_identity", ["prompt_id": id]) }
        policy.promptFailed(at: now)
        promptID = nil
    }
}

func sample() {
    let now = Date(); let epoch = now.timeIntervalSince1970
    checkPrompt(epoch)
    let current = collectProcesses()
    guard let ticks = cpuTicks(), let old = previous else { previous = cpuTicks(); eventLog("host_collection_failed"); return }
    let uptime = ProcessInfo.processInfo.systemUptime; let elapsed = uptime - previousUptime
    previous = ticks; previousUptime = uptime
    guard let cpu = hostCPU(old, ticks) else { return }
    var snapshot = processReport(previous: previousProcesses, current: current, logicalCores: ProcessInfo.processInfo.activeProcessorCount)
    previousProcesses = current
    snapshot.merge(telemetry.sample()) { _, new in new }
    snapshot["time"] = iso.string(from: now); snapshot["cpu_percent"] = cpu; snapshot["memory_pressure"] = pressure()
    snapshot["build_version"] = buildVersion; snapshot["logical_cores"] = ProcessInfo.processInfo.activeProcessorCount; snapshot["host_sample_seconds"] = elapsed
    let rows = snapshot["top"] as? [[String: Any]] ?? []
    let processes = snapshot["top_processes"] as? [[String: Any]] ?? []
    let ws = rows.first { ($0["path"] as? String ?? "").hasSuffix("/WindowServer") }?["cpu_core_percent"] as? Double ?? 0
    let topIdentity = processes.first?["action_identity"] as? [String: Any]
    let topID = topIdentity.map { "\($0["pid"] ?? ""):\($0["start_seconds"] ?? ""):\($0["start_microseconds"] ?? "")" }
    let decision = policy.evaluate(IncidentSignal(now: epoch, cpu: cpu, pressure: pressure(), swapInMBps: snapshot["swap_in_mbps"] as? Double ?? 0, swapOutMBps: snapshot["swap_out_mbps"] as? Double ?? 0, windowServerCPU: ws, topProcessCPU: processes.first?["cpu_core_percent"] as? Double ?? 0, thermal: snapshot["thermal_state"] as? Int ?? 0, topProcessID: topID))
    snapshot["alert_reasons"] = decision.reasons; snapshot["severity"] = decision.severity
    writeJSON(snapshot, "latest.json")
    let day = String(iso.string(from: now).prefix(10)); append(snapshot, "samples-\(day).jsonl")
    if once { exit(0) }
    if !current.collected || !current.jobsCollected, epoch - lastFailureLog > 60 { lastFailureLog = epoch; eventLog("sampling_degraded", ["processes_collected": current.collected, "jobs_collected": current.jobsCollected]) }
    do {
        let existing = store.currentID
        let incident = try store.observe(snapshot: snapshot, decision: decision, now: epoch)
        if let incident = incident { lastAdvice = incident }
        else {
            let previousID = lastAdvice["id"] ?? lastAdvice["previous_incident_id"] ?? ""
            lastAdvice = ["latest": snapshot, "status": "monitoring", "severity": decision.severity,
                          "reasons": decision.reasons, "analysis": incidentAnalysis(snapshot: snapshot, reasons: decision.reasons), "previous_incident_id": previousID]
        }
        if existing == nil && store.currentID != nil {
            eventLog("incident_started", ["incident_id": store.currentID ?? "", "reasons": decision.reasons])
            if let incident = incident { launchCapture(incident) }
        }
        if decision.recovered { eventLog("incident_recovered", ["incident_id": existing ?? ""]) }
        writeJSON(lastAdvice, "latest-advice.json")
        if let id = lastAdvice["id"] as? String, let text = try? String(contentsOf: root.appendingPathComponent("incidents/\(id).md"), encoding: .utf8) { try text.write(to: root.appendingPathComponent("latest-advice.md"), atomically: true, encoding: .utf8) }
        else {
            let analysis = lastAdvice["analysis"] as? [String: Any] ?? [:]
            let text = "# 当前资源观察\n\n采样时间：\(snapshot["time"] ?? "")（UTC）\n\n" + ((analysis["facts"] as? [String] ?? []) + (analysis["recommendations"] as? [String] ?? [])).joined(separator: "\n\n") + "\n\n" + (analysis["learning_summary"] as? String ?? "")
            try text.write(to: root.appendingPathComponent("latest-advice.md"), atomically: true, encoding: .utf8)
        }
    } catch { eventLog("incident_write_failed", ["error": String(describing: error)]) }
    menu?.update(cpu: cpu, severity: decision.severity, incident: store.currentID != nil)
    if decision.shouldPrompt && !once { launchPrompt() }
    if day != lastDay {
        lastDay = day
        let cutoff = now.addingTimeInterval(-max(1, number("retention_days")) * 86400)
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] where url.lastPathComponent.hasPrefix("samples-") && url.pathExtension == "jsonl" {
            if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < cutoff { do { try FileManager.default.removeItem(at: url) } catch { logError("retention: \(error)") } }
        }
        let incidentCutoff = now.timeIntervalSince1970 - max(14, number("incident_retention_days")) * 86400
        for url in (try? FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url), let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], record["status"] as? String != "active", let start = record["started_epoch"] as? Double, start < incidentCutoff else { continue }
            do {
                let id = url.deletingPathExtension().lastPathComponent
                guard UUID(uuidString: id) != nil else { continue }
                try FileManager.default.removeItem(at: url)
                let md = url.deletingPathExtension().appendingPathExtension("md"); if FileManager.default.fileExists(atPath: md.path) { try FileManager.default.removeItem(at: md) }
                for child in try FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil) where child.lastPathComponent == id + "-diagnostics.json" || (child.lastPathComponent.hasPrefix(id + "-sample-") && child.pathExtension == "txt") { try FileManager.default.removeItem(at: child) }
            } catch { logError("incident retention: \(error)") }
        }
    }
    if once { exit(0) }
}
if !once {
    let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching()
    menu = ResourceMenu(showAdvice: { launchPrompt(manual: true) }, openEvidence: { NSWorkspace.shared.open(root.appendingPathComponent("incidents")) })
    eventLog("monitor_started", ["pid": ProcessInfo.processInfo.processIdentifier])
}
let timer = Timer.scheduledTimer(withTimeInterval: once ? 2 : max(5, number("interval_seconds")), repeats: true) { _ in sample() }
if once { RunLoop.main.run() } else { NSApplication.shared.run() }
