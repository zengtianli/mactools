import Foundation

var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    passed += 1
}
func reading(_ pid: Int, _ parent: Int, _ time: Double, _ path: String = "/Python.app/Contents/MacOS/Python", _ started: String = "Mon Sep 14 12:00:00 2026") -> ProcessReading {
    ProcessReading(pid: pid, ppid: parent, startedAt: started, cpuSeconds: time, rssKB: 2048, path: path)
}
func sample(_ rows: [ProcessReading], _ uptime: Double, _ jobs: [Int: String] = [:]) -> ProcessSample {
    ProcessSample(uptime: uptime, rows: Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) }), jobs: jobs, parseFailures: 0, collected: true, jobsCollected: true)
}

check(cpuTimeSeconds("900:04.95") == 54004.95, "TIME minutes are cumulative, not CPU percent")
check(cpuTimeSeconds("1-02:03:04.50") == 93784.5, "day/hour TIME format")
check(cpuTimeSeconds("invalid") == nil, "invalid TIME is not zero")
let (parsed, failures) = parseProcesses(" 12 1 Mon Sep 14 12:00:00 2026 900:04.95 2048 S /Applications/Resource Watch.app/Contents/MacOS/resource-watch\ninvalid")
check(parsed[12]?.path == "/Applications/Resource Watch.app/Contents/MacOS/resource-watch" && failures == 1, "parse spaced app paths and report bad rows")
check(parsed[12]?.stat == "S", "process state is sampled without command arguments")
let (padded, _) = parseProcesses(" 12 1 Mon Sep 14 12:00:00 2026 900:04.95 2048 S    /Applications/Resource Watch.app/Contents/MacOS/resource-watch")
check(padded[12]?.path == "/Applications/Resource Watch.app/Contents/MacOS/resource-watch", "ps state column padding cannot become part of the executable path")
check(parseJobs("PID Status Label\n12 0 com.tianli.report\n- 0 com.tianli.waiting\n13 0 com.notifhub.daemon\n14 0 cyou.tianli.agent\n15 0 com.apple.ignored").count == 3, "only running managed jobs have root PIDs")

// Two Python jobs and a grandchild must remain distinct. Each own CPU delta is
// counted once; ancestry is not an inclusive CPU total to sum for every node.
let before = sample([reading(10, 1, 100), reading(11, 10, 20), reading(12, 11, 10), reading(20, 1, 50), reading(30, 1, 5), reading(40, 1, 100), reading(50, 1, 100)], 100)
let after = sample([reading(10, 1, 101), reading(11, 10, 22), reading(12, 11, 13), reading(20, 1, 52), reading(30, 1, 6), reading(40, 1, 2, "/Python.app/Contents/MacOS/Python", "Mon Sep 14 12:01:00 2026"), reading(60, 1, 20)], 110, [10: "com.tianli.first", 20: "com.tianli.second"])
let report = processReport(previous: before, current: after, logicalCores: 10)
let jobs = report["managed_jobs"] as! [[String: Any]]
let first = jobs.first { $0["managed_job"] as? String == "com.tianli.first" }!
let second = jobs.first { $0["managed_job"] as? String == "com.tianli.second" }!
check(first["cpu_core_percent"] as? Double == 60 && first["cpu_machine_percent"] as? Double == 6, "10-second delta and logical-core normalization")
check(first["pids"] as? [Int] == [10, 11, 12], "deep descendants are owned once by the job")
check(second["cpu_core_percent"] as? Double == 20, "unrelated Python job stays separate")
let coverage = report["process_coverage"] as! [String: Any]
check(coverage["measured"] as? Int == 5 && coverage["new_or_reset"] as? Int == 2 && coverage["exited_since_previous"] as? Int == 1, "new, reused and exited PIDs remain explicit unknown coverage")
let details = report["top_processes"] as! [[String: Any]]
check(details.first { $0["pid"] as? Int == 40 }!["cpu_core_percent"] is NSNull, "PID reuse cannot produce a false CPU spike")
check(details.first { $0["pid"] as? Int == 12 }!["ancestor_pids"] as? [Int] == [11, 10], "nested ancestry is preserved")
let flattened = (report["top"] as! [[String: Any]]).flatMap { $0["pids"] as! [Int] }
check(flattened.count == Set(flattened).count && flattened.count == 7, "no double counting across app and job groups")
let cycle = sample([reading(71, 72, 1), reading(72, 71, 1)], 2)
check(ancestors(of: cycle.rows[71]!, in: cycle.rows).count == 2, "racing/cyclic parent data terminates")
let reset = processReport(previous: sample([reading(80, 1, 100)], 20), current: sample([reading(80, 1, 2)], 30), logicalCores: 10)
check((reset["process_coverage"] as! [String: Any])["measured"] as? Int == 0, "CPU counter reset is not negative usage")
let zeroWindow = processReport(previous: after, current: after, logicalCores: 10)
check((zeroWindow["process_coverage"] as! [String: Any])["measured"] as? Int == 0, "zero-duration sample is not a CPU measurement")
check(JSONSerialization.isValidJSONObject(report), "null coverage and numeric fields serialize to JSON")

// Memory ranking starts from the entire snapshot, not the CPU top 15.
let busyBefore = (100..<120).map { reading($0, 1, 0, "/busy-\($0)") }
let busyAfter = (100..<120).map { reading($0, 1, 100, "/busy-\($0)") }
let idleLarge = ProcessReading(pid: 130, ppid: 1, startedAt: "same", cpuSeconds: 0, rssKB: 1024 * 1024, path: "/idle-memory")
let memoryReport = processReport(previous: sample(busyBefore + [idleLarge], 10), current: sample(busyAfter + [idleLarge], 20), logicalCores: 8)
check(!(memoryReport["top"] as! [[String: Any]]).contains { $0["path"] as? String == "/idle-memory" }, "memory fixture lies outside CPU top 15")
check((memoryReport["top_memory"] as! [[String: Any]]).first?["path"] as? String == "/idle-memory", "idle large process appears first in memory groups")
check((memoryReport["top_memory_processes"] as! [[String: Any]]).first?["pid"] as? Int == 130, "RSS process ranking uses all observed processes")

let browser = reading(200, 1, 0, "/Applications/Browser.app/Contents/MacOS/Browser")
let browserWorker = reading(201, 200, 0, "/usr/local/bin/node")
let terminal = reading(210, 1, 0, "/Applications/Ghostty.app/Contents/MacOS/ghostty")
let shell = reading(211, 210, 0, "/bin/zsh")
let terminalWorker = reading(212, 211, 0, "/usr/local/bin/python3")
let ancestry = sample([browser, browserWorker, terminal, shell, terminalWorker], 20)
let ancestryReport = processReport(previous: ancestry, current: ancestry, logicalCores: 8)
let ancestryDetails = ancestryReport["top_processes"] as! [[String: Any]]
check(ancestryDetails.first { $0["pid"] as? Int == 201 }?["group"] as? String == "/Applications/Browser.app", "non-app GUI child inherits nearest app parent")
check(ancestryDetails.first { $0["pid"] as? Int == 212 }?["terminal_protected"] as? Bool == true, "deep terminal descendant remains protected")
check(ancestryDetails.first { $0["pid"] as? Int == 201 }?["terminal_protected"] as? Bool == false, "ordinary GUI worker is distinguishable from terminal tasks")
let zombie = ProcessReading(pid: 220, ppid: 200, startedAt: "same", cpuSeconds: 0, rssKB: 0, path: "/zombie", stat: "Z")
let zombieReport = processReport(previous: sample([zombie], 1), current: sample([zombie], 2), logicalCores: 8)
check(zombieReport["zombie_count"] as? Int == 1, "zombie state is diagnostic evidence, not automatic cleanup authorization")

let identity1 = ProcessIdentity(pid: 240, parentPID: 1, userID: 501, startSeconds: 100, startMicroseconds: 1)
let identity2 = ProcessIdentity(pid: 240, parentPID: 1, userID: 501, startSeconds: 100, startMicroseconds: 2)
let quick1 = ProcessReading(pid: 240, ppid: 1, startedAt: "same second", cpuSeconds: 1, rssKB: 10, path: "/quick", identity: identity1)
let quick2 = ProcessReading(pid: 240, ppid: 1, startedAt: "same second", cpuSeconds: 2, rssKB: 10, path: "/quick", identity: identity2)
let quickReport = processReport(previous: sample([quick1], 1), current: sample([quick2], 2), logicalCores: 8)
check((quickReport["process_coverage"] as! [String: Any])["measured"] as? Int == 0, "microsecond identity rejects PID reuse inside the same ps start second")
check(processIdentity(Int(getpid()))?.pid == Int(getpid()), "live identity can be read for the test process")

let normal = samplingCommand("/bin/echo", ["sampling-ok"])
check(normal.output == "sampling-ok\n" && normal.health["succeeded"] as? Bool == true, "bounded command preserves successful output")
let missing = samplingCommand("/nonexistent/resource-watch-test", [])
check(missing.output == nil && missing.health["error"] as? String == "spawn_failed", "spawn error is explicit health evidence")
let failed = samplingCommand("/bin/sh", ["-c", "exit 7"])
check(failed.output == nil && failed.health["exit_code"] as? Int32 == 7, "nonzero exit is distinct from empty successful output")
let overflow = samplingCommand("/usr/bin/yes", ["fixture"], timeout: 1, outputLimit: 1024)
check(overflow.output == nil && overflow.health["output_truncated"] as? Bool == true, "unbounded output cannot exhaust sampler memory")

let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("resource-watch-owned-child-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: temporary) }
let unrelated = Process()
unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep"); unrelated.arguments = ["10"]
try unrelated.run()
defer { if unrelated.isRunning { unrelated.terminate() } }
let unrelatedIdentity = processIdentity(Int(unrelated.processIdentifier))!
let timeoutStart = ProcessInfo.processInfo.systemUptime
let timed = samplingCommand("/bin/sh", ["-c", "trap '' TERM; sleep 20 & printf '%s' \"$!\" > \"$1\"; wait", "fixture", temporary.path], timeout: 0.15)
check(timed.output == nil && timed.health["timed_out"] as? Bool == true, "hung command times out")
check(ProcessInfo.processInfo.systemUptime - timeoutStart < 1.5, "TERM-ignoring command cannot block sampling indefinitely")
check(timed.health["cleanup_scope"] as? String == "owned_unreaped_child_process_group" && timed.health["child_reaped"] as? Bool == true, "cleanup is limited to owned group while PID reuse is impossible")
let childPID = Int((try? String(contentsOf: temporary, encoding: .utf8)) ?? "")!
Thread.sleep(forTimeInterval: 0.15)
check(processIdentity(childPID) == nil, "timeout also ends the sampler-created child process")
check(unrelated.isRunning && processIdentity(Int(unrelated.processIdentifier)).map { unrelatedIdentity.sameInstance(as: $0) } == true,
      "timeout cleanup leaves an unrelated running process instance untouched")
unrelated.terminate()
let exitedParent = samplingCommand("/bin/sh", ["-c", "sleep 20 & exit 0"], timeout: 0.15)
check(exitedParent.health["timed_out"] as? Bool == true && exitedParent.health["child_reaped"] as? Bool == true, "descendant holding stdout open is bounded after its parent exits")

let firstCounter = SwapCounterReading(uptime: 100, wallTime: 1000, swapInPages: 100, swapOutPages: 200)
let nextCounter = SwapCounterReading(uptime: 110, wallTime: 1010, swapInPages: 740, swapOutPages: 1480)
check(swapRates(previous: nil, current: firstCounter, pageSize: 16384)["swap_in_mbps"] is NSNull, "first swap sample has no invented zero rate")
let rates = swapRates(previous: firstCounter, current: nextCounter, pageSize: 16384)
check(rates["swap_in_mbps"] as? Double == 1 && rates["swap_out_mbps"] as? Double == 2, "swap rates use page size and real sample seconds")
let gap = SwapCounterReading(uptime: 300, wallTime: 1200, swapInPages: 740, swapOutPages: 1480)
check(swapRates(previous: firstCounter, current: gap, pageSize: 16384)["swap_in_mbps"] is NSNull, "sampling gap invalidates swap rate")
let sleepGap = SwapCounterReading(uptime: 110, wallTime: 1200, swapInPages: 740, swapOutPages: 1480)
check(swapRates(previous: firstCounter, current: sleepGap, pageSize: 16384)["swap_in_mbps"] is NSNull, "sleep or wall-clock discontinuity invalidates swap rate")
let resetCounter = SwapCounterReading(uptime: 110, wallTime: 1010, swapInPages: 1, swapOutPages: 2)
check(swapRates(previous: firstCounter, current: resetCounter, pageSize: 16384)["swap_rate_status"] as? String == "counter_reset", "counter reset is recorded")
let telemetry = SystemTelemetrySampler().sample()
check(JSONSerialization.isValidJSONObject(telemetry) && telemetry["telemetry_health"] is [String: Any], "live telemetry is JSON serializable and reports collection health")
check(telemetry["swap_in_mbps"] is NSNull, "live first snapshot preserves unknown swap rate")
print("PASS: \(passed) process sampling, command cleanup and telemetry checks")
