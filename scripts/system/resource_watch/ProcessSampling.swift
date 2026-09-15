import Foundation
import Darwin

// The start timestamp is read from the kernel, including microseconds. PIDs alone
// are never an identity, and a ps lstart timestamp has only second precision.
struct ProcessIdentity: Equatable {
    let pid: Int
    let parentPID: Int
    let userID: Int
    let startSeconds: UInt64
    let startMicroseconds: UInt64
    var json: [String: Any] {
        ["pid": pid, "ppid": parentPID, "uid": userID,
         "start_seconds": startSeconds, "start_microseconds": startMicroseconds]
    }
    func sameInstance(as other: ProcessIdentity) -> Bool {
        pid == other.pid && startSeconds == other.startSeconds && startMicroseconds == other.startMicroseconds
    }
}

func processIdentity(_ pid: Int) -> ProcessIdentity? {
    guard pid > 0 && pid <= Int(Int32.max) else { return nil }
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(Int32(pid), PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return ProcessIdentity(pid: Int(info.pbi_pid), parentPID: Int(info.pbi_ppid), userID: Int(info.pbi_uid),
                           startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
}

// ps TIME is cumulative CPU used by this process, without -S child-time folding.
// A two-snapshot difference puts process and host readings on the same window.
struct ProcessReading {
    let pid: Int
    let ppid: Int
    let startedAt: String
    let cpuSeconds: Double
    let rssKB: Int
    let path: String
    let stat: String
    let identity: ProcessIdentity?
    init(pid: Int, ppid: Int, startedAt: String, cpuSeconds: Double, rssKB: Int, path: String,
         stat: String = "?", identity: ProcessIdentity? = nil) {
        self.pid = pid; self.ppid = ppid; self.startedAt = startedAt; self.cpuSeconds = cpuSeconds
        self.rssKB = rssKB; self.path = path; self.stat = stat; self.identity = identity
    }
}

struct ProcessSample {
    let uptime: Double
    let rows: [Int: ProcessReading]
    let jobs: [Int: String]
    let parseFailures: Int
    let collected: Bool
    let jobsCollected: Bool
    var collectionHealth: [String: Any] = [:]
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
        let fields = line.split(maxSplits: 10, whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count == 11, let pid = Int(fields[0]), let ppid = Int(fields[1]),
              let cpu = cpuTimeSeconds(String(fields[7])), let rss = Int(fields[8]) else {
            failures += 1; continue
        }
        rows[pid] = ProcessReading(pid: pid, ppid: ppid, startedAt: fields[2...6].joined(separator: " "),
                                   cpuSeconds: cpu, rssKB: rss,
                                   path: String(fields[10].drop(while: { $0 == " " || $0 == "\t" })), stat: String(fields[9]))
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

struct SamplingCommandResult {
    let output: String?
    let health: [String: Any]
}

// A command and its descendants get a new process group. The parent intentionally
// does not reap its direct child until cleanup is finished: the child PID/group
// number then cannot be reused, even if the child exited before its descendants.
// This function can only signal the group returned by its own posix_spawn call.
func samplingCommand(_ path: String, _ arguments: [String], timeout: Double = 3,
                     outputLimit: Int = 4 * 1024 * 1024) -> SamplingCommandResult {
    let began = ProcessInfo.processInfo.systemUptime
    var health: [String: Any] = ["command": URL(fileURLWithPath: path).lastPathComponent,
                               "succeeded": false, "timed_out": false, "output_truncated": false]
    func finish(_ output: String? = nil) -> SamplingCommandResult {
        health["duration_seconds"] = ProcessInfo.processInfo.systemUptime - began
        return SamplingCommandResult(output: output, health: health)
    }
    guard timeout.isFinite && timeout > 0 && outputLimit > 0 else {
        health["error"] = "invalid_command_limits"; return finish()
    }
    var descriptors: [Int32] = [0, 0]
    guard pipe(&descriptors) == 0 else { health["error"] = "pipe_failed"; health["errno"] = errno; return finish() }
    defer { close(descriptors[0]) }
    _ = fcntl(descriptors[0], F_SETFD, FD_CLOEXEC)
    _ = fcntl(descriptors[1], F_SETFD, FD_CLOEXEC)
    _ = fcntl(descriptors[0], F_SETFL, O_NONBLOCK)
    var actions: posix_spawn_file_actions_t?; var attributes: posix_spawnattr_t?
    posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
    defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
    posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO)
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addclose(&actions, descriptors[0]); posix_spawn_file_actions_addclose(&actions, descriptors[1])
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
    posix_spawnattr_setpgroup(&attributes, 0)
    var environment = ProcessInfo.processInfo.environment; environment["LC_ALL"] = "C"
    var argv = ([path] + arguments).map { strdup($0) } + [nil]
    var envp = environment.sorted(by: { $0.key < $1.key }).map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer { for pointer in argv { free(pointer) }; for pointer in envp { free(pointer) } }
    var pid: pid_t = 0
    let spawned = posix_spawn(&pid, path, &actions, &attributes, &argv, &envp)
    close(descriptors[1])
    guard spawned == 0 else { health["error"] = "spawn_failed"; health["errno"] = spawned; return finish() }
    health["owned_pid"] = pid; health["owned_process_group"] = pid
    var data = Data(); var buffer = [UInt8](repeating: 0, count: 16384)
    var exited = false; var eof = false; var ownershipLost = false; var cleanupReason: String?
    func observeExit() {
        var information = siginfo_t()
        let result = waitid(P_PID, id_t(pid), &information, WEXITED | WNOHANG | WNOWAIT)
        if result == 0 { exited = information.si_pid == pid }
        else if errno == ECHILD { ownershipLost = true }
    }
    while true {
        // Bound work per read pass as well as output size; a noisy writer cannot
        // indefinitely keep us inside a pipe-draining loop.
        for _ in 0..<64 {
            let count = read(descriptors[0], &buffer, buffer.count)
            if count > 0 {
                let remaining = max(0, outputLimit - data.count)
                data.append(contentsOf: buffer.prefix(min(count, remaining)))
                if count > remaining { cleanupReason = "output_limit"; health["output_truncated"] = true; break }
            } else if count == 0 { eof = true; break }
            else if errno == EAGAIN || errno == EWOULDBLOCK { break }
            else if errno != EINTR { cleanupReason = "read_failed"; health["errno"] = errno; break }
        }
        observeExit()
        if ownershipLost { cleanupReason = "child_ownership_lost"; break }
        if let _ = cleanupReason { break }
        if exited && eof { break }
        if ProcessInfo.processInfo.systemUptime - began >= timeout {
            cleanupReason = "timeout"; health["timed_out"] = true; break
        }
        Thread.sleep(forTimeInterval: 0.01)
    }
    if let reason = cleanupReason {
        health["error"] = reason
        // WNOWAIT retains the owned child, including when it is already a zombie.
        // If ownership was lost, skip every signal rather than risk a reused PID.
        if !ownershipLost && getpgid(pid) == pid {
            health["cleanup_scope"] = "owned_unreaped_child_process_group"
            let term = kill(-pid, SIGTERM); health["cleanup_term_sent"] = term == 0
            Thread.sleep(forTimeInterval: 0.10)
            let killed = kill(-pid, SIGKILL); health["cleanup_kill_sent"] = killed == 0
            health["cleanup_group_gone"] = killed != 0 && errno == ESRCH
        } else { health["cleanup_skipped"] = "child_ownership_or_private_group_not_verified" }
    }
    var status: Int32 = 0
    let reapDeadline = ProcessInfo.processInfo.systemUptime + 0.3
    var reaped: pid_t = 0
    repeat {
        reaped = waitpid(pid, &status, WNOHANG)
        if reaped != 0 { break }
        Thread.sleep(forTimeInterval: 0.01)
    } while ProcessInfo.processInfo.systemUptime < reapDeadline
    health["child_reaped"] = reaped == pid
    if reaped == 0 {
        // Uninterruptible kernel sleep must not block monitoring. Dispatch observes
        // eventual exit and reaps only this still-owned child, without waiting.
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global(qos: .utility))
        source.setEventHandler { var later: Int32 = 0; _ = waitpid(pid, &later, WNOHANG); source.cancel() }
        source.resume(); health["cleanup_pending"] = true
    }
    if reaped == pid {
        let signal = status & 0x7f
        if signal == 0 { health["exit_code"] = (status >> 8) & 0xff }
        else { health["termination_signal"] = signal }
        if cleanupReason == nil && signal == 0 && (status >> 8) & 0xff == 0 {
            health["succeeded"] = true; return finish(String(decoding: data, as: UTF8.self))
        }
        if cleanupReason == nil { health["error"] = "nonzero_exit" }
    }
    return finish()
}

func commandOutput(_ path: String, _ arguments: [String]) -> String? {
    samplingCommand(path, arguments).output
}

func collectProcesses() -> ProcessSample {
    let result = samplingCommand("/bin/ps", ["-axo", "pid=,ppid=,lstart=,time=,rss=,stat=,comm="])
    let uptime = ProcessInfo.processInfo.systemUptime
    let (parsed, failures) = parseProcesses(result.output ?? "")
    let startFormatter = DateFormatter()
    startFormatter.locale = Locale(identifier: "en_US_POSIX")
    startFormatter.timeZone = ProcessInfo.processInfo.environment["TZ"].flatMap { TimeZone(identifier: $0) } ?? .current
    startFormatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
    var parsedStarts: [String: Double] = [:]
    let rows = parsed.mapValues { row in
        let start = parsedStarts[row.startedAt] ?? startFormatter.date(from: row.startedAt)?.timeIntervalSince1970
        if let start = start { parsedStarts[row.startedAt] = start }
        let live = processIdentity(row.pid)
        // Do not attach a replacement instance's identity to an earlier ps row.
        // Missing/inaccessible/racing identity stays null, so it cannot authorize an action.
        let identity = live.flatMap { value in
            value.parentPID == row.ppid && start == Double(value.startSeconds) ? value : nil
        }
        return ProcessReading(pid: row.pid, ppid: row.ppid, startedAt: row.startedAt, cpuSeconds: row.cpuSeconds,
                              rssKB: row.rssKB, path: row.path, stat: row.stat, identity: identity)
    }
    let jobResult = samplingCommand("/bin/launchctl", ["list"])
    let jobs = parseJobs(jobResult.output ?? "")
    return ProcessSample(uptime: uptime, rows: rows, jobs: jobs, parseFailures: failures,
                         collected: result.output != nil, jobsCollected: jobResult.output != nil,
                         collectionHealth: ["ps": result.health, "launchctl": jobResult.health])
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

func terminalProcessPath(_ path: String) -> Bool {
    let executableNames: Set<String> = ["ghostty", "terminal", "iterm2", "iterm", "alacritty", "kitty", "wezterm-gui", "warp",
                                        "codex", "claude", "nvim", "vim", "emacs", "ssh", "tmux", "screen", "sh", "zsh", "bash", "fish"]
    let parts = path.lowercased().split(separator: "/").map(String.init)
    return executableNames.contains(parts.last ?? "")
        || parts.filter { $0.hasSuffix(".app") }.contains { executableNames.contains(String($0.dropLast(4))) }
}

func terminalProtected(_ chain: [ProcessReading]) -> Bool {
    chain.contains { terminalProcessPath($0.path) }
}

func processReport(previous: ProcessSample, current: ProcessSample, logicalCores: Int) -> [String: Any] {
    let seconds = current.uptime - previous.uptime
    let cores = Double(max(1, logicalCores))
    var details: [[String: Any]] = []
    var groups: [String: (cpu: Double, rss: Int, pids: [Int], unknown: Int, job: String?, protected: Bool, zombies: Int)] = [:]
    var measured = 0
    for process in current.rows.values.sorted(by: { $0.pid < $1.pid }) {
        let chain = ancestors(of: process, in: current.rows)
        let job = chain.compactMap { current.jobs[$0.pid] }.first
        let ownApp = appGroup(process.path)
        let inheritedApp = chain.dropFirst().first { $0.path.contains(".app/") }.map { appGroup($0.path) }
        let key = job.map { "job:" + $0 } ?? (process.path.contains(".app/") || ownApp != process.path ? ownApp : inheritedApp ?? ownApp)
        let protected = terminalProtected(chain)
        let old = previous.rows[process.pid]
        let identityMatches = process.identity.flatMap { identity in old?.identity.map { identity.sameInstance(as: $0) } } ?? (old?.startedAt == process.startedAt)
        let valid = previous.collected && current.collected && seconds > 0 && identityMatches && process.cpuSeconds >= (old?.cpuSeconds ?? .infinity)
        let cpu: Double? = valid ? 100 * (process.cpuSeconds - old!.cpuSeconds) / seconds : nil
        if cpu != nil { measured += 1 }
        var group = groups[key] ?? (0, 0, [], 0, job, false, 0)
        group.cpu += cpu ?? 0; group.rss += process.rssKB; group.pids.append(process.pid); group.unknown += cpu == nil ? 1 : 0
        group.protected = group.protected || protected; group.zombies += process.stat.contains("Z") ? 1 : 0
        groups[key] = group
        details.append([
            "pid": process.pid, "ppid": process.ppid, "started_at": process.startedAt, "path": process.path,
            "group": key, "managed_job": job as Any? ?? NSNull(),
            "stat": process.stat, "is_zombie": process.stat.contains("Z"), "rss_mb": Double(process.rssKB) / 1024,
            "terminal_protected": protected, "action_identity": process.identity?.json as Any? ?? NSNull(),
            "cpu_core_percent": cpu as Any? ?? NSNull(), "cpu_machine_percent": cpu.map { $0 / cores } as Any? ?? NSNull(),
            "ancestor_pids": chain.dropFirst().map { $0.pid },
            "ancestor_paths": chain.dropFirst().map { $0.path }
        ])
    }
    let ordered = groups.map { key, value -> [String: Any] in
        // Keep original-instance identities for possible UI actions. Only a
        // group's app executables or launchd root are actionable targets; storing
        // every helper identity would unnecessarily enlarge every sample log.
        let targets = details.filter { detail in
            guard detail["group"] as? String == key else { return false }
            let pid = detail["pid"] as! Int, path = detail["path"] as! String
            return current.jobs[pid] == value.job && value.job != nil
                || (key.hasSuffix(".app") && path.hasPrefix(key + "/Contents/MacOS/"))
        }.prefix(8).map { detail -> [String: Any] in
            ["pid": detail["pid"]!, "ppid": detail["ppid"]!, "path": detail["path"]!,
             "started_at": detail["started_at"]!, "action_identity": detail["action_identity"]!,
             "stat": detail["stat"]!, "terminal_protected": detail["terminal_protected"]!]
        }
        return ["path": key, "cpu_core_percent": value.cpu, "cpu_machine_percent": value.cpu / cores,
         "rss_mb_sum": value.rss / 1024, "processes": value.pids.count, "pids": value.pids,
         "unmeasured_processes": value.unknown, "managed_job": value.job as Any? ?? NSNull(),
         "terminal_protected": value.protected, "zombie_processes": value.zombies, "action_targets": Array(targets)]
    }.sorted {
        let left = $0["cpu_core_percent"] as! Double, right = $1["cpu_core_percent"] as! Double
        return left == right ? ($0["path"] as! String) < ($1["path"] as! String) : left > right
    }
    let top = details.sorted {
        let left = $0["cpu_core_percent"] as? Double ?? -1, right = $1["cpu_core_percent"] as? Double ?? -1
        return left == right ? ($0["pid"] as! Int) < ($1["pid"] as! Int) : left > right
    }
    let memoryGroups = ordered.sorted {
        let left = $0["rss_mb_sum"] as! Int, right = $1["rss_mb_sum"] as! Int
        return left == right ? ($0["path"] as! String) < ($1["path"] as! String) : left > right
    }
    let memoryDetails = details.sorted {
        let left = $0["rss_mb"] as! Double, right = $1["rss_mb"] as! Double
        return left == right ? ($0["pid"] as! Int) < ($1["pid"] as! Int) : left > right
    }
    let exited = previous.rows.keys.filter { current.rows[$0] == nil }.count
    return [
        "process_cpu_method": "cumulative_time_delta", "process_sample_seconds": max(0, seconds),
        "process_cpu_unit": "100% = one logical core; machine percentage divides by logical_cores",
        "process_coverage": ["observed": current.rows.count, "measured": measured,
                             "new_or_reset": current.rows.count - measured, "exited_since_previous": exited,
                             "parse_failures": current.parseFailures, "collection_succeeded": current.collected,
                             "job_collection_succeeded": current.jobsCollected],
        "process_coverage_note": "Each PID is counted once. New, exited, inaccessible and between-sample processes are not fully measured; process totals need not equal host CPU. Ancestors are context, not additional CPU. RSS sums may double-count shared pages. Z means already exited and awaiting parent reaping; killing a zombie does not free CPU or memory.",
        "top": Array(ordered.prefix(15)), "top_processes": Array(top.prefix(15)),
        "top_memory": Array(memoryGroups.prefix(15)), "top_memory_processes": Array(memoryDetails.prefix(15)),
        "zombie_count": details.filter { $0["is_zombie"] as? Bool == true }.count,
        "zombie_processes": Array(details.filter { $0["is_zombie"] as? Bool == true }.prefix(15)),
        "managed_jobs": ordered.filter { $0["managed_job"] is String }, "collection_health": current.collectionHealth
    ]
}
