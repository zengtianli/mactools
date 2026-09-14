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
let (parsed, failures) = parseProcesses(" 12 1 Mon Sep 14 12:00:00 2026 900:04.95 2048 /Applications/Resource Watch.app/Contents/MacOS/resource-watch\ninvalid")
check(parsed[12]?.path == "/Applications/Resource Watch.app/Contents/MacOS/resource-watch" && failures == 1, "parse spaced app paths and report bad rows")
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
print("PASS: \(passed) process sampling and job attribution checks")
