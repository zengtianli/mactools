import Foundation

// ps TIME is cumulative CPU used by this process, without -S child-time folding.
// A two-snapshot difference puts process and host readings on the same window.
struct ProcessReading {
    let pid: Int
    let ppid: Int
    let startedAt: String
    let cpuSeconds: Double
    let rssKB: Int
    let path: String
}

struct ProcessSample {
    let uptime: Double
    let rows: [Int: ProcessReading]
    let jobs: [Int: String]
    let parseFailures: Int
    let collected: Bool
    let jobsCollected: Bool
}

func cpuTimeSeconds(_ text: String) -> Double? {
    let dayParts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard dayParts.count <= 2 else { return nil }
    let days = dayParts.count == 2 ? Double(dayParts[0]) : 0
    let clock = dayParts.last!.split(separator: ":", omittingEmptySubsequences: false)
    guard let days = days, days >= 0, (2...3).contains(clock.count) else { return nil }
    var seconds = 0.0
    for component in clock {
        guard let number = Double(component), number >= 0, number.isFinite else { return nil }
        seconds = seconds * 60 + number
    }
    return days * 86400 + seconds
}

func parseProcesses(_ text: String) -> ([Int: ProcessReading], Int) {
    var rows: [Int: ProcessReading] = [:]
    var failures = 0
    for line in text.split(separator: "\n") {
        // lstart has five fields; comm may contain spaces. LC_ALL=C fixes lstart.
        let fields = line.split(maxSplits: 9, whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count == 10, let pid = Int(fields[0]), let ppid = Int(fields[1]),
              let cpu = cpuTimeSeconds(String(fields[7])), let rss = Int(fields[8]) else {
            failures += 1; continue
        }
        rows[pid] = ProcessReading(pid: pid, ppid: ppid, startedAt: fields[2...6].joined(separator: " "),
                                   cpuSeconds: cpu, rssKB: rss, path: String(fields[9]))
    }
    return (rows, failures)
}

func parseJobs(_ text: String) -> [Int: String] {
    var jobs: [Int: String] = [:]
    for line in text.split(separator: "\n") {
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count == 3, let pid = Int(fields[0]), pid > 0 else { continue }
        let label = String(fields[2])
        // Same prefixes as the existing jobs controller; waiting jobs have no PID.
        if ["com.tianli.", "cyou.tianli.", "com.notifhub."].contains(where: label.hasPrefix) { jobs[pid] = label }
    }
    return jobs
}

func commandOutput(_ path: String, _ arguments: [String]) -> String? {
    let task = Process(); task.executableURL = URL(fileURLWithPath: path); task.arguments = arguments
    var environment = ProcessInfo.processInfo.environment; environment["LC_ALL"] = "C"; task.environment = environment
    let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
    guard (try? task.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
    return task.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
}

func collectProcesses() -> ProcessSample {
    let text = commandOutput("/bin/ps", ["-axo", "pid=,ppid=,lstart=,time=,rss=,comm="])
    let uptime = ProcessInfo.processInfo.systemUptime
    let (rows, failures) = parseProcesses(text ?? "")
    let jobText = commandOutput("/bin/launchctl", ["list"])
    let jobs = parseJobs(jobText ?? "")
    return ProcessSample(uptime: uptime, rows: rows, jobs: jobs, parseFailures: failures, collected: text != nil, jobsCollected: jobText != nil)
}

func ancestors(of process: ProcessReading, in rows: [Int: ProcessReading]) -> [ProcessReading] {
    var result = [process]; var visited: Set<Int> = [process.pid]; var pid = process.ppid
    while let parent = rows[pid], !visited.contains(pid) {
        result.append(parent); visited.insert(pid); pid = parent.ppid
    }
    return result
}

func appGroup(_ path: String) -> String {
    if path.contains("/CoreSimulator/") { return "iOS 模拟器（全部设备）" }
    if let end = path.range(of: ".app/") { return String(path[..<end.lowerBound]) + ".app" }
    return path
}

func processReport(previous: ProcessSample, current: ProcessSample, logicalCores: Int) -> [String: Any] {
    let seconds = current.uptime - previous.uptime
    let cores = Double(max(1, logicalCores))
    var details: [[String: Any]] = []
    var groups: [String: (cpu: Double, rss: Int, pids: [Int], unknown: Int, job: String?)] = [:]
    var measured = 0
    for process in current.rows.values.sorted(by: { $0.pid < $1.pid }) {
        let chain = ancestors(of: process, in: current.rows)
        let job = chain.compactMap { current.jobs[$0.pid] }.first
        let key = job.map { "job:" + $0 } ?? appGroup(process.path)
        let old = previous.rows[process.pid]
        let valid = previous.collected && current.collected && seconds > 0 && old?.startedAt == process.startedAt && process.cpuSeconds >= (old?.cpuSeconds ?? .infinity)
        let cpu: Double? = valid ? 100 * (process.cpuSeconds - old!.cpuSeconds) / seconds : nil
        if cpu != nil { measured += 1 }
        var group = groups[key] ?? (0, 0, [], 0, job)
        group.cpu += cpu ?? 0; group.rss += process.rssKB; group.pids.append(process.pid); group.unknown += cpu == nil ? 1 : 0
        groups[key] = group
        details.append([
            "pid": process.pid, "ppid": process.ppid, "started_at": process.startedAt, "path": process.path,
            "group": key, "managed_job": job as Any? ?? NSNull(),
            "cpu_core_percent": cpu as Any? ?? NSNull(), "cpu_machine_percent": cpu.map { $0 / cores } as Any? ?? NSNull(),
            "ancestor_pids": chain.dropFirst().map { $0.pid },
            "ancestor_paths": chain.dropFirst().map { $0.path }
        ])
    }
    let ordered = groups.map { key, value -> [String: Any] in
        ["path": key, "cpu_core_percent": value.cpu, "cpu_machine_percent": value.cpu / cores,
         "rss_mb_sum": value.rss / 1024, "processes": value.pids.count, "pids": value.pids,
         "unmeasured_processes": value.unknown, "managed_job": value.job as Any? ?? NSNull()]
    }.sorted { ($0["cpu_core_percent"] as! Double) > ($1["cpu_core_percent"] as! Double) }
    let top = details.sorted { ($0["cpu_core_percent"] as? Double ?? -1) > ($1["cpu_core_percent"] as? Double ?? -1) }
    let exited = previous.rows.keys.filter { current.rows[$0] == nil }.count
    return [
        "process_cpu_method": "cumulative_time_delta", "process_sample_seconds": max(0, seconds),
        "process_cpu_unit": "100% = one logical core; machine percentage divides by logical_cores",
        "process_coverage": ["observed": current.rows.count, "measured": measured,
                             "new_or_reset": current.rows.count - measured, "exited_since_previous": exited,
                             "parse_failures": current.parseFailures, "collection_succeeded": current.collected,
                             "job_collection_succeeded": current.jobsCollected],
        "process_coverage_note": "Each PID is counted once. New, exited, inaccessible and between-sample processes are not fully measured; process totals need not equal host CPU. Ancestors are context, not additional CPU.",
        "top": Array(ordered.prefix(15)), "top_processes": Array(top.prefix(15)),
        "managed_jobs": ordered.filter { $0["managed_job"] is String }
    ]
}
