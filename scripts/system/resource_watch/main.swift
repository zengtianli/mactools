import Cocoa
import Darwin

// CPU percentages in process rows follow ps: 100% means one logical core.
let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ResourceWatch")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
func processes() -> [[String: Any]] {
    let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/ps")
    task.arguments = ["-axo", "pid=,pcpu=,rss=,comm="]
    let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
    guard (try? task.run()) != nil else { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
    var groups: [String: (Double, Int, Int)] = [:]
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let cols = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
        guard cols.count == 4, let cpu = Double(cols[1]), let rss = Int(cols[2]) else { continue }
        let path = String(cols[3]); var key = path
        if path.contains("/CoreSimulator/") { key = "iOS 模拟器（全部设备）" }
        else if let end = path.range(of: ".app/") { key = String(path[..<end.lowerBound]) + ".app" }
        let old = groups[key] ?? (0, 0, 0); groups[key] = (old.0 + cpu, old.1 + rss, old.2 + 1)
    }
    return groups.sorted { $0.value.0 > $1.value.0 }.prefix(15).map { key, value in
        ["path": key, "cpu_core_percent": value.0, "rss_mb_sum": value.1 / 1024, "processes": value.2]
    }
}

if CommandLine.arguments.contains("--prompt") || CommandLine.arguments.contains("--preview") {
    let preview = CommandLine.arguments.contains("--preview")
    let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching()
    let data = try Data(contentsOf: root.appendingPathComponent("latest.json"))
    let snapshot = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let rows = snapshot["top"] as? [[String: Any]] ?? []
    let alert = NSAlert(); alert.messageText = preview ? "资源监控 · 弹窗预览" : "Mac 持续高负载"
    let cpu = snapshot["cpu_percent"] as? Double ?? 0
    alert.informativeText = String(format: "整机 CPU %.0f%%。请选择要正常退出的应用。\n进程 CPU：100%% 表示占满一个核心；内存为 RSS 合计估算。\n取消或忽略不会关闭任何程序。", cpu)
    alert.addButton(withTitle: "暂不关闭"); alert.addButton(withTitle: preview ? "预览确认（不退出）" : "退出勾选应用")
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 280))
    var choices: [(NSButton, String)] = []
    let running = NSWorkspace.shared.runningApplications
    for (i, row) in rows.prefix(8).enumerated() {
        let path = row["path"] as? String ?? ""
        let name = URL(fileURLWithPath: path).lastPathComponent
        let title = String(format: "%@   %.0f%% CPU · %d MB", name, row["cpu_core_percent"] as? Double ?? 0, row["rss_mb_sum"] as? Int ?? 0)
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
let configURL = root.appendingPathComponent("config.json")
if !FileManager.default.fileExists(atPath: configURL.path) { writeJSON(defaults, "config.json") }
let config = (try? JSONSerialization.jsonObject(with: Data(contentsOf: configURL))) as? [String: Any] ?? defaults
func number(_ key: String) -> Double { (config[key] as? NSNumber)?.doubleValue ?? (defaults[key] as! NSNumber).doubleValue }
var previous = cpuTicks(); var highSince: Date?; var prompt: Process?
var lastAlert = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "resourceWatchLastAlert"))
var lastSample = Date(); var lastDay = ""
let once = CommandLine.arguments.contains("--once")
func sample() {
    let now = Date()
    guard let ticks = cpuTicks(), let old = previous else { previous = cpuTicks(); return }
    previous = ticks
    let deltas = zip(ticks, old).map { Double($0 &- $1) }; let total = deltas.reduce(0, +)
    guard total > 0 else { return }
    let cpu = 100 * (1 - deltas[2] / total); let mem = pressure()
    if now.timeIntervalSince(lastSample) > max(45, number("interval_seconds") * 3) { highSince = nil }
    lastSample = now
    let snapshot: [String: Any] = ["time": iso.string(from: now), "cpu_percent": cpu, "memory_pressure": mem, "logical_cores": ProcessInfo.processInfo.activeProcessorCount, "top": processes()]
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
