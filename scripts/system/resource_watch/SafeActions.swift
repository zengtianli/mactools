import Cocoa
import Darwin

// Eligibility is independent of CPU thresholds: busy, idle and zombie are not
// permission to stop a process. Only an explicit GUI confirmation calls actions.
func protectedResourcePath(_ path: String) -> Bool {
    let value = path.lowercased()
    return terminalProcessPath(path) || ["resource-watch", "resource watch.app", "windowserver", "finder.app", "loginwindow", "shadowrocket", "orbstack", "todesk", "atrust", "karabiner"].contains(where: value.contains)
        || path.hasPrefix("/System/") || path.hasPrefix("/usr/") || path.hasPrefix("/sbin/") || path.hasPrefix("/bin/")
}

struct ResourceApplication {
    let pid: Int
    let path: String
    let bundleIdentifier: String?
    let regular: Bool
    init(pid: Int, path: String, bundleIdentifier: String? = nil, regular: Bool = true) {
        self.pid = pid; self.path = path; self.bundleIdentifier = bundleIdentifier; self.regular = regular
    }
    init(_ app: NSRunningApplication) {
        self.init(pid: Int(app.processIdentifier), path: app.bundleURL?.path ?? "",
                  bundleIdentifier: app.bundleIdentifier, regular: app.activationPolicy == .regular)
    }
}

func resourceSnapshotFresh(_ snapshot: [String: Any], now: Date = Date()) -> Bool {
    guard let text = snapshot["time"] as? String else { return false }
    let format = ISO8601DateFormatter()
    let parsed = format.date(from: text) ?? {
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.date(from: text)
    }()
    guard let date = parsed else { return false }
    return now.timeIntervalSince(date) >= -5 && now.timeIntervalSince(date) <= 60
}

func candidateProcessIdentity(_ candidate: [String: Any]) -> ProcessIdentity? {
    guard let identity = candidate["action_identity"] as? [String: Any],
          let pid = identity["pid"] as? Int, let ppid = identity["ppid"] as? Int,
          let uid = identity["uid"] as? Int,
          let seconds = identity["start_seconds"] as? NSNumber, let micros = identity["start_microseconds"] as? NSNumber,
          pid > 1, ppid >= 0, uid >= 0, seconds.doubleValue >= 0, seconds.doubleValue.isFinite,
          seconds.doubleValue.rounded() == seconds.doubleValue,
          micros.doubleValue >= 0, micros.doubleValue < 1_000_000, micros.doubleValue.rounded() == micros.doubleValue else { return nil }
    return ProcessIdentity(pid: pid, parentPID: ppid, userID: uid,
                           startSeconds: seconds.uint64Value, startMicroseconds: micros.uint64Value)
}

func sameResourceIdentity(candidate: [String: Any], live: ProcessReading?, userID: Int = Int(getuid())) -> Bool {
    guard let live = live, let expected = candidateProcessIdentity(candidate), let identity = live.identity else { return false }
    return live.pid > 1 && live.pid == candidate["pid"] as? Int
        && live.startedAt == candidate["started_at"] as? String && live.path == candidate["executable"] as? String
        && expected.userID == userID && identity.userID == userID && expected.sameInstance(as: identity)
        && identity.parentPID == live.ppid
}

func eligibleResourceKind(path: String, label: String?, live: ProcessReading, processes: ProcessSample,
                          app: ResourceApplication?, userID: Int = Int(getuid())) -> String {
    guard !protectedResourcePath(path), !live.stat.contains("Z"),
          let identity = live.identity, identity.userID == userID,
          !terminalProtected(ancestors(of: live, in: processes.rows)) else { return "protected" }
    if let app = app, app.pid == live.pid, app.path == path, app.regular,
       app.bundleIdentifier != "com.apple.finder", appGroup(live.path) == path,
       !protectedResourcePath(live.path) { return "app_quit" }
    if path.hasPrefix("/Library/Input Methods/"), path.hasSuffix(".app"),
       live.path.hasPrefix(path + "/Contents/MacOS/"), appGroup(live.path) == path,
       !protectedResourcePath(live.path) { return "input_restart" }
    if label == "com.tianli.md-index-graph", processes.jobs[live.pid] == label { return "job_pause" }
    return "protected"
}

func resourceCandidates(snapshot: [String: Any], memoryFirst: Bool) -> [[String: Any]] {
    resourceCandidates(snapshot: snapshot, memoryFirst: memoryFirst, processes: collectProcesses(),
                       apps: NSWorkspace.shared.runningApplications.map(ResourceApplication.init))
}

// Pure overload for regression fixtures. Never fill an old incident with newly
// discovered process identities: its original sampled instance must still match.
func resourceCandidates(snapshot: [String: Any], memoryFirst: Bool, processes: ProcessSample,
                        apps: [ResourceApplication], now: Date = Date(), userID: Int = Int(getuid())) -> [[String: Any]] {
    let rows = snapshot[memoryFirst ? "top_memory" : "top"] as? [[String: Any]] ?? []
    let details = (snapshot["top_processes"] as? [[String: Any]] ?? []) + (snapshot["top_memory_processes"] as? [[String: Any]] ?? [])
    let fresh = resourceSnapshotFresh(snapshot, now: now)
    return rows.prefix(10).map { row in
        let path = row["path"] as? String ?? "", label = row["managed_job"] as? String
        let app = apps.first { $0.path == path && $0.regular }
        let pids = row["pids"] as? [Int] ?? []
        let targets = (row["action_targets"] as? [[String: Any]]) ?? details.filter { pids.contains($0["pid"] as? Int ?? 0) }
        let sampled = app.flatMap { app in targets.first { $0["pid"] as? Int == app.pid } }
            ?? targets.first { target in
                let pid = target["pid"] as? Int ?? 0
                return app == nil && (label != nil ? processes.jobs[pid] == label : appGroup(target["path"] as? String ?? "") == path)
            }
        var candidate: [String: Any] = ["path": path, "name": label ?? URL(fileURLWithPath: path).lastPathComponent,
                                       "kind": "protected", "pid": sampled?["pid"] ?? 0,
                                       "started_at": sampled?["started_at"] ?? "", "executable": sampled?["path"] ?? "",
                                       "action_identity": sampled?["action_identity"] ?? NSNull(), "label": label ?? "",
                                       "sample_time": snapshot["time"] ?? "",
                                       "cpu_core_percent": row["cpu_core_percent"] ?? 0, "rss_mb_sum": row["rss_mb_sum"] ?? 0]
        let pid = candidate["pid"] as? Int ?? 0
        var kind = "protected", blocked = "受保护、身份缺失或实例已变更，仅展示诊断。"
        if !fresh { blocked = "采样超过 60 秒或时间未知；刷新后再决定。" }
        else if row["terminal_protected"] as? Bool == true || sampled?["terminal_protected"] as? Bool == true {
            blocked = "包含终端或编程任务，按约定保留。"
        } else if let live = processes.rows[pid], sameResourceIdentity(candidate: candidate, live: live, userID: userID) {
            kind = eligibleResourceKind(path: path, label: label, live: live, processes: processes, app: app, userID: userID)
        }
        let impact: String
        switch kind {
        case "app_quit": impact = "请求正常退出；可能出现保存提示，应用可拒绝。确认没有正在进行的工作后再选。"
        case "input_restart": impact = "结束本用户的这个输入法实例，由系统按需重新启动；尚未上屏的文字可能丢失。"
        case "job_pause": impact = "暂停知识图谱扫描与查询服务；可用 jobs/ctl resume md-index-graph 恢复。"
        default: impact = blocked
        }
        candidate["kind"] = kind; candidate["impact"] = impact
        candidate["recommendation"] = kind == "protected" ? "推荐保留，查看原因分析" : "确认当前不用后，可勾选退出；默认保留"
        return candidate
    }
}

// A bulk recommendation is deliberately narrower than manual eligibility.
// Document/editing apps stay available for an individual, informed selection,
// but never enter the one-click recommendation because save state is unknown.
func documentResourcePath(_ path: String) -> Bool {
    let names: Set<String> = [
        "microsoft word", "microsoft excel", "microsoft powerpoint", "microsoft onenote", "microsoft outlook",
        "word", "excel", "powerpoint", "onenote", "outlook", "pages", "numbers", "keynote",
        "xcode", "visual studio code", "visual studio code - insiders", "vscode", "code", "code - insiders",
        "cursor", "windsurf", "zed", "android studio", "intellij idea", "intellij idea ce", "pycharm", "webstorm",
        "textedit", "notes", "preview", "obsidian", "typora", "marktext", "sublime text", "bbedit", "notion",
        "wps office", "wpsoffice", "libreoffice", "onlyoffice", "onlyoffice desktop editors",
        "sketch", "figma", "affinity designer", "affinity designer 2", "affinity photo", "affinity photo 2"
    ]
    return path.lowercased().split(separator: "/").contains { component in
        guard component.hasSuffix(".app") else { return false }
        let name = String(component.dropLast(4))
        return names.contains(name) || ["adobe photoshop", "adobe illustrator", "adobe indesign", "adobe premiere", "final cut pro", "logic pro"].contains(where: name.hasPrefix)
    }
}

// Returns only the proposed choices; it neither checks UI boxes nor dispatches
// actions. The caller may select these after the user presses "select recommended".
func recommendedResourceCandidates(_ candidates: [[String: Any]], memoryFirst: Bool,
                                   now: Date = Date()) -> [[String: Any]] {
    let metric = memoryFirst ? "rss_mb_sum" : "cpu_core_percent"
    let threshold = memoryFirst ? 512.0 : 30.0
    let eligible = candidates.filter { candidate in
        guard candidate["kind"] as? String == "app_quit",
              candidate["terminal_protected"] as? Bool != true,
              let path = candidate["path"] as? String, let executable = candidate["executable"] as? String,
              path.hasSuffix(".app"), !protectedResourcePath(path), !protectedResourcePath(executable),
              !documentResourcePath(path), !documentResourcePath(executable),
              (candidate["label"] as? String ?? "").isEmpty,
              let identity = candidateProcessIdentity(candidate), identity.pid == candidate["pid"] as? Int,
              resourceSnapshotFresh(["time": candidate["sample_time"] ?? ""], now: now),
              let value = (candidate[metric] as? NSNumber)?.doubleValue, value.isFinite, value >= threshold else { return false }
        return true
    }.sorted { left, right in
        let lhs = (left[metric] as! NSNumber).doubleValue, rhs = (right[metric] as! NSNumber).doubleValue
        if lhs != rhs { return lhs > rhs }
        let leftPath = left["path"] as! String, rightPath = right["path"] as! String
        return leftPath == rightPath ? (left["pid"] as! Int) < (right["pid"] as! Int) : leftPath < rightPath
    }
    var seen = Set<String>()
    return eligible.filter { candidate in
        // Repeated CPU/memory views of one app do not use several of the slots.
        seen.insert(candidate["path"] as! String).inserted
    }.prefix(3).map { candidate in
        var result = candidate
        let value = (candidate[metric] as! NSNumber).doubleValue
        result["recommendation_selected"] = true
        result["recommendation_reason"] = memoryFirst
            ? String(format: "内存 RSS 合计约 %.0f MB，达到 512 MB 推荐阈值；含共享页，实际释放量以退出后测量为准。", value)
            : String(format: "CPU %.0f%% 单核，达到 30%% 推荐阈值；正常退出可减少该应用的负载，可能出现保存提示。", value)
        return result
    }
}

// The sole signal action is a confirmed input-method restart. It requires a
// same-user, microsecond identity and a fresh parent-chain check. No automatic
// user-process killing, forceQuit, SIGKILL, app deletion or broad pattern kills.
func performResourceAction(_ candidate: [String: Any]) -> [String: Any] {
    let kind = candidate["kind"] as? String ?? "protected", path = candidate["path"] as? String ?? ""
    let pid = candidate["pid"] as? Int ?? 0
    var result: [String: Any] = ["event": "action_result", "kind": kind, "path": path, "pid": pid]
    guard resourceSnapshotFresh(["time": candidate["sample_time"] ?? ""]) else {
        result["outcome"] = "blocked_stale_snapshot"; return result
    }
    let processes = collectProcesses()
    guard let live = processes.rows[pid], !protectedResourcePath(path), sameResourceIdentity(candidate: candidate, live: live) else {
        result["outcome"] = "blocked_identity_or_protected"; return result
    }
    if terminalProtected(ancestors(of: live, in: processes.rows)) {
        result["outcome"] = "blocked_terminal_ancestry"; return result
    }
    let runningApp = NSRunningApplication(processIdentifier: pid_t(pid))
    let app = runningApp.map(ResourceApplication.init)
    let eligible = eligibleResourceKind(path: path, label: candidate["label"] as? String, live: live, processes: processes, app: app)
    guard kind != "protected", kind == eligible else { result["outcome"] = "blocked_kind_or_app_changed"; return result }
    // Re-read the kernel immediately before dispatch, closing the collection/UI
    // delay. macOS exposes PID signals, not pidfds; no broad or forced kill follows.
    guard let expected = candidateProcessIdentity(candidate), let immediate = processIdentity(pid),
          expected.sameInstance(as: immediate), immediate.userID == Int(getuid()), immediate.parentPID == live.ppid else {
        result["outcome"] = "blocked_identity_changed_before_request"; return result
    }
    switch kind {
    case "app_quit":
        guard let runningApp = runningApp, runningApp.bundleURL?.path == path,
              runningApp.activationPolicy == .regular else { result["outcome"] = "blocked_app_changed"; return result }
        result["requested"] = runningApp.terminate()
    case "input_restart":
        result["requested"] = kill(pid_t(pid), SIGTERM) == 0
        if result["requested"] as? Bool == false { result["errno"] = errno }
    case "job_pause":
        let controller = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Dev/jobs/ctl").path
        let command = samplingCommand(controller, ["pause", "md-index-graph"])
        result["requested"] = command.output != nil; result["command_health"] = command.health
        result["restore"] = "~/Dev/jobs/ctl resume md-index-graph"
    default: result["outcome"] = "blocked_kind"; return result
    }
    // Observe the original instance only, so a replacement process is neither
    // treated as failure nor acted upon. Save dialogs/refusal never escalate.
    let deadline = ProcessInfo.processInfo.systemUptime + 3
    while ProcessInfo.processInfo.systemUptime < deadline,
          let identity = processIdentity(pid), expected.sameInstance(as: identity) {
        Thread.sleep(forTimeInterval: 0.1)
    }
    let remaining = processIdentity(pid).map { expected.sameInstance(as: $0) } ?? false
    result["outcome"] = remaining ? "still_running_or_awaiting_save" : "original_process_exited"
    return result
}
