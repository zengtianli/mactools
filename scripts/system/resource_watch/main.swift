import Cocoa
import Darwin

// Process rows use interval CPU deltas: 100% means one logical core.
let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ResourceWatch")
let iso = ISO8601DateFormatter()
func writeJSON(_ value: Any, _ name: String) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
    try? data.write(to: root.appendingPathComponent(name), options: .atomic)
}
func append(_ value: [String: Any], _ name: String) {
    guard var data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
    data.append(10)
    let url = root.appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
    if let file = try? FileHandle(forWritingTo: url) { defer { try? file.close() }; try? file.seekToEnd(); try? file.write(contentsOf: data) }
}
func cpuTicks() -> [UInt32]? {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { p in
        p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
    }
    guard result == KERN_SUCCESS else { return nil }
    return [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
}
func pressure() -> Int {
    var value: Int32 = 0; var size = MemoryLayout<Int32>.size
    return sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 ? Int(value) : 0
}
func hostCPU(_ old: [UInt32], _ ticks: [UInt32]) -> Double? {
    let deltas = zip(ticks, old).map { Double($0 &- $1) }; let total = deltas.reduce(0, +)
    return total > 0 ? 100 * (1 - deltas[2] / total) : nil
}

// Read-only diagnostics exit before creating state, taking the daemon lock or starting UI.
if let index = CommandLine.arguments.firstIndex(of: "--diagnose") {
    let argument = CommandLine.arguments.dropFirst(index + 1).first ?? "2"
    guard let seconds = Double(argument), seconds.isFinite, (1...60).contains(seconds) else {
        FileHandle.standardError.write(Data("--diagnose expects 1–60 seconds\n".utf8)); exit(2)
    }
    let oldProcesses = collectProcesses(); let oldTicks = cpuTicks()
    let began = ProcessInfo.processInfo.systemUptime
    Thread.sleep(forTimeInterval: seconds)
    let currentProcesses = collectProcesses()
    let ticks = cpuTicks(); let elapsed = ProcessInfo.processInfo.systemUptime - began
    var snapshot = processReport(previous: oldProcesses, current: currentProcesses, logicalCores: ProcessInfo.processInfo.activeProcessorCount)
    snapshot["time"] = iso.string(from: Date()); snapshot["read_only"] = true
    snapshot["logical_cores"] = ProcessInfo.processInfo.activeProcessorCount
    snapshot["host_sample_seconds"] = elapsed; snapshot["memory_pressure"] = pressure()
    snapshot["cpu_percent"] = oldTicks.flatMap { old in ticks.flatMap { hostCPU(old, $0) } } as Any? ?? NSNull()
    let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys, .prettyPrinted])
    FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
    if !oldProcesses.collected || !currentProcesses.collected || !currentProcesses.jobsCollected {
        FileHandle.standardError.write(Data("Process/job collection failed; attribution is incomplete.\n".utf8)); exit(3)
    }
    exit(0)
}

try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
if CommandLine.arguments.contains("--prompt") || CommandLine.arguments.contains("--preview") {
    let preview = CommandLine.arguments.contains("--preview")
    let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching()
    let data = try Data(contentsOf: root.appendingPathComponent("latest.json"))
    let snapshot = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let rows = snapshot["top"] as? [[String: Any]] ?? []
    let alert = NSAlert(); alert.messageText = preview ? "资源监控 · 弹窗预览" : "Mac 持续高负载"
    let cpu = snapshot["cpu_percent"] as? Double ?? 0
    let cores = snapshot["logical_cores"] as? Int ?? 1
    alert.informativeText = String(format: "整机 CPU %.0f%%（%d 个逻辑核心）。请选择要正常退出的应用。\n清单按采样期间的 CPU 增量计算；100%% 单核 = 一个核心。\n后台任务包含深层子进程，内存为 RSS 合计估算。取消或忽略不会关闭任何程序。", cpu, cores)
    alert.addButton(withTitle: "暂不关闭"); alert.addButton(withTitle: preview ? "预览确认（不退出）" : "退出勾选应用")
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 280))
    var choices: [(NSButton, String)] = []
    let running = NSWorkspace.shared.runningApplications
    for (i, row) in rows.prefix(8).enumerated() {
        let path = row["path"] as? String ?? ""
        let name = row["managed_job"] as? String ?? URL(fileURLWithPath: path).lastPathComponent
        let coreCPU = row["cpu_core_percent"] as? Double ?? 0
        let machineCPU = row["cpu_machine_percent"] as? Double ?? coreCPU / Double(max(1, cores))
        let partial = (row["unmeasured_processes"] as? Int ?? 0) > 0 ? "≥" : ""
        let title = String(format: "%@   %@%.0f%% 整机（%.0f%% 单核）· %d MB", name, partial, machineCPU, coreCPU, row["rss_mb_sum"] as? Int ?? 0)
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.frame = NSRect(x: 0, y: 245 - i * 32, width: 520, height: 30)
        button.isEnabled = path == "iOS 模拟器（全部设备）" || running.contains { $0.bundleURL?.path == path && $0.activationPolicy == .regular && $0.bundleIdentifier != "com.apple.finder" }
        view.addSubview(button); choices.append((button, path))
    }
    alert.accessoryView = view
    app.activate(ignoringOtherApps: true)
    // A single prompt expires, with no action, after 90 seconds.
    DispatchQueue.main.asyncAfter(deadline: .now() + 90) { app.abortModal() }
    let response = alert.runModal()
    if response == .alertSecondButtonReturn && !preview {
        for (button, path) in choices where button.state == .on && button.isEnabled {
            if path == "iOS 模拟器（全部设备）" {
                let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun"); task.arguments = ["simctl", "shutdown", "all"]
                do { try task.run(); task.waitUntilExit(); append(["time": iso.string(from: Date()), "action": "simulator_shutdown_all", "exit_code": task.terminationStatus], "actions.jsonl") } catch { append(["time": iso.string(from: Date()), "action": "simulator_shutdown_failed"], "actions.jsonl") }
                continue
            }
            for target in running where target.bundleURL?.path == path && target.activationPolicy == .regular {
                let requested = target.terminate() // allows the application's normal save/cancel flow
                append(["time": iso.string(from: Date()), "app": path, "pid": target.processIdentifier, "quit_requested": requested], "actions.jsonl")
            }
        }
    }
    exit(0)
}

let defaults: [String: Any] = ["interval_seconds": 15, "cpu_threshold": 90, "sustained_seconds": 60, "cooldown_seconds": 1800, "retention_days": 14]
let lockFD = open(root.appendingPathComponent("monitor.lock").path, O_CREAT | O_RDWR, 0o600)
if !CommandLine.arguments.contains("--once") && (lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0) { exit(0) }
let configURL = root.appendingPathComponent("config.json")
if !FileManager.default.fileExists(atPath: configURL.path) { writeJSON(defaults, "config.json") }
let config = (try? JSONSerialization.jsonObject(with: Data(contentsOf: configURL))) as? [String: Any] ?? defaults
func number(_ key: String) -> Double { (config[key] as? NSNumber)?.doubleValue ?? (defaults[key] as! NSNumber).doubleValue }
var previousProcesses = collectProcesses()
var previous = cpuTicks(); var previousUptime = ProcessInfo.processInfo.systemUptime
var highSince: Date?; var prompt: Process?
var lastAlert = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "resourceWatchLastAlert"))
var lastSample = Date(); var lastDay = ""
let once = CommandLine.arguments.contains("--once")
func sample() {
    let now = Date()
    let currentProcesses = collectProcesses()
    guard let ticks = cpuTicks(), let old = previous else { previous = cpuTicks(); return }
    let uptime = ProcessInfo.processInfo.systemUptime; let elapsed = uptime - previousUptime
    previous = ticks; previousUptime = uptime
    guard let cpu = hostCPU(old, ticks) else { return }
    let mem = pressure()
    if now.timeIntervalSince(lastSample) > max(45, number("interval_seconds") * 3) { highSince = nil }
    lastSample = now
    var snapshot = processReport(previous: previousProcesses, current: currentProcesses, logicalCores: ProcessInfo.processInfo.activeProcessorCount)
    previousProcesses = currentProcesses
    snapshot["time"] = iso.string(from: now); snapshot["cpu_percent"] = cpu; snapshot["memory_pressure"] = mem
    snapshot["logical_cores"] = ProcessInfo.processInfo.activeProcessorCount; snapshot["host_sample_seconds"] = elapsed
    writeJSON(snapshot, "latest.json")
    let day = String(iso.string(from: now).prefix(10))
    append(snapshot, "samples-\(day).jsonl")
    if day != lastDay {
        lastDay = day
        let cutoff = now.addingTimeInterval(-max(1, number("retention_days")) * 86400)
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] where url.lastPathComponent.hasPrefix("samples-") {
            if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }
    if cpu >= number("cpu_threshold") || mem == 4 { if highSince == nil { highSince = now } } else { highSince = nil }
    if !once, let since = highSince, now.timeIntervalSince(since) >= number("sustained_seconds"), now.timeIntervalSince(lastAlert) >= number("cooldown_seconds"), prompt?.isRunning != true {
        lastAlert = now; UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "resourceWatchLastAlert")
        let task = Process(); task.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); task.arguments = ["--prompt"]
        try? task.run(); prompt = task
        append(["time": iso.string(from: now), "event": "overload_prompt", "cpu_percent": cpu, "memory_pressure": mem], "actions.jsonl")
    }
    if once { exit(0) }
}
let timer = Timer.scheduledTimer(withTimeInterval: once ? 2 : max(5, number("interval_seconds")), repeats: true) { _ in sample() }
RunLoop.main.run()
