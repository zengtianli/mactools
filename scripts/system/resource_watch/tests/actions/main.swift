import Cocoa
import Darwin

var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }; passed += 1
}
let fixtureUser = 501, fixtureNow = Date()
func reading(_ pid: Int, path: String, parent: Int = 1, uid: Int = fixtureUser, micros: UInt64 = 123, stat: String = "S") -> ProcessReading {
    ProcessReading(pid: pid, ppid: parent, startedAt: "same second", cpuSeconds: 1, rssKB: 1024, path: path, stat: stat,
                   identity: ProcessIdentity(pid: pid, parentPID: parent, userID: uid, startSeconds: 123456, startMicroseconds: micros))
}
func sample(_ rows: [ProcessReading], jobs: [Int: String] = [:]) -> ProcessSample {
    ProcessSample(uptime: 10, rows: Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) }), jobs: jobs,
                  parseFailures: 0, collected: true, jobsCollected: true)
}
func snapshot(_ rows: [ProcessReading], jobs: [Int: String] = [:], time: Date = fixtureNow) -> [String: Any] {
    let processes = sample(rows, jobs: jobs)
    var result = processReport(previous: processes, current: processes, logicalCores: 8)
    result["time"] = ISO8601DateFormatter().string(from: time)
    return result
}
func candidates(_ snap: [String: Any], rows: [ProcessReading], apps: [ResourceApplication] = [], jobs: [Int: String] = [:]) -> [[String: Any]] {
    resourceCandidates(snapshot: snap, memoryFirst: false, processes: sample(rows, jobs: jobs), apps: apps, now: fixtureNow, userID: fixtureUser)
}
let appPath = "/Applications/Fixture.app", executable = "/Applications/Fixture.app/Contents/MacOS/Fixture"
let original = reading(100, path: executable)
let app = ResourceApplication(pid: 100, path: appPath)
let originalSnapshot = snapshot([original])
let candidate = candidates(originalSnapshot, rows: [original], apps: [app])[0]
check(candidate["kind"] as? String == "app_quit", "same-user original app instance permits only normal quit")
check(sameResourceIdentity(candidate: candidate, live: original, userID: fixtureUser), "kernel microsecond identity matches")
let reused = reading(100, path: executable, micros: 124)
check(!sameResourceIdentity(candidate: candidate, live: reused, userID: fixtureUser), "same PID/path/start second with different microseconds is rejected")
check(candidates(originalSnapshot, rows: [reused], apps: [app])[0]["kind"] as? String == "protected", "old incident cannot bind its PID to a replacement instance")
let restarted = reading(101, path: executable)
check(candidates(originalSnapshot, rows: [restarted], apps: [ResourceApplication(pid: 101, path: appPath)])[0]["kind"] as? String == "protected", "same app path with new PID cannot inherit old incident action")
check(candidates(snapshot([original], time: fixtureNow.addingTimeInterval(-61)), rows: [original], apps: [app])[0]["kind"] as? String == "protected", "stale snapshots have no selectable actions")
check(candidates(snapshot([original], time: fixtureNow.addingTimeInterval(10)), rows: [original], apps: [app])[0]["kind"] as? String == "protected", "future clock change does not authorize an action")
var legacy = originalSnapshot
legacy["top"] = [["path": appPath, "pids": [100]]]; legacy["top_processes"] = []; legacy["top_memory_processes"] = []
check(candidates(legacy, rows: [original], apps: [app])[0]["kind"] as? String == "protected", "legacy samples missing identity cannot borrow a current identity")
let foreign = reading(100, path: executable, uid: 502)
check(candidates(snapshot([foreign]), rows: [foreign], apps: [app])[0]["kind"] as? String == "protected", "other user's application cannot be selected")
for path in ["/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", "/Applications/Ghostty.app", "/Applications/Codex.app", "/System/Applications/Utilities/Terminal.app"] {
    check(protectedResourcePath(path), "system and terminal applications remain protected: \(path)")
}
let terminal = reading(200, path: "/Applications/Ghostty.app/Contents/MacOS/ghostty")
let shell = reading(201, path: "/bin/zsh", parent: 200)
let childApp = reading(100, path: executable, parent: 201)
check(candidates(snapshot([childApp, shell, terminal]), rows: [childApp, shell, terminal], apps: [app]).first { $0["path"] as? String == appPath }?["kind"] as? String == "protected", "terminal descendant is not selectable even when it is a regular app")
check(candidates(originalSnapshot, rows: [childApp, shell, terminal], apps: [app])[0]["kind"] as? String == "protected", "current parent chain is rechecked after snapshot creation")
let zombie = reading(100, path: executable, stat: "Z")
check(candidates(snapshot([zombie]), rows: [zombie], apps: [app])[0]["kind"] as? String == "protected", "zombie label never authorizes a kill")
let inputPath = "/Library/Input Methods/FixtureIME.app/Contents/MacOS/FixtureIME"
let input = reading(300, path: inputPath)
let inputCandidate = candidates(snapshot([input]), rows: [input])[0]
check(inputCandidate["kind"] as? String == "input_restart", "input-method restart is restricted to exact current-user app instance")
check(candidates(snapshot([input]), rows: [reading(300, path: inputPath, micros: 999)])[0]["kind"] as? String == "protected", "input-method PID reuse is blocked")
let otherInput = reading(300, path: inputPath, uid: 0)
check(candidates(snapshot([otherInput]), rows: [otherInput])[0]["kind"] as? String == "protected", "root input method cannot be signalled by this action")
var fakeInput = inputCandidate; fakeInput["executable"] = "/bin/sleep"
check(!sameResourceIdentity(candidate: fakeInput, live: input, userID: fixtureUser), "input executable substitution is rejected")
let job = reading(400, path: "/opt/homebrew/bin/python3")
check(candidates(snapshot([job], jobs: [400: "com.tianli.md-index-graph"]), rows: [job], jobs: [400: "com.tianli.md-index-graph"])[0]["kind"] as? String == "job_pause", "only the explicitly supported managed job is pausable")
let graphSnapshot = snapshot([job], jobs: [400: "com.tianli.md-index-graph"])
check(candidates(graphSnapshot, rows: [job], jobs: [400: "com.tianli.other"])[0]["kind"] as? String == "protected", "job label is rechecked at candidate creation")

// The actual dispatch function also fails closed before touching any process.
check(performResourceAction(["kind": "input_restart", "pid": Int(getpid()), "path": "/Library/Input Methods/Fake.app"])["outcome"] as? String == "blocked_stale_snapshot", "actual action endpoint rejects missing freshness")

func recommendation(_ name: String, cpu: Double = 80, memory: Double = 1024, pid: Int = 100) -> [String: Any] {
    var result = candidate
    result["path"] = "/Applications/\(name).app"; result["executable"] = "/Applications/\(name).app/Contents/MacOS/\(name)"
    result["pid"] = pid; result["action_identity"] = ProcessIdentity(pid: pid, parentPID: 1, userID: fixtureUser, startSeconds: 123456, startMicroseconds: 123).json
    result["cpu_core_percent"] = cpu; result["rss_mb_sum"] = memory
    return result
}
let browserRecommendation = recommendation("Browser")
let selected = recommendedResourceCandidates([browserRecommendation], memoryFirst: false, now: fixtureNow)
check(selected.count == 1 && selected[0]["recommendation_selected"] as? Bool == true, "one-click recommendation includes a fresh eligible high-CPU app")
check((selected[0]["recommendation_reason"] as? String)?.contains("80%") == true, "recommendation explains the actual CPU measurement")
var staleRecommendation = browserRecommendation
staleRecommendation["sample_time"] = ISO8601DateFormatter().string(from: fixtureNow.addingTimeInterval(-61))
check(recommendedResourceCandidates([staleRecommendation], memoryFirst: false, now: fixtureNow).isEmpty, "bulk recommendation rejects stale choices")
let excludedNames = ["Ghostty", "Codex", "Terminal", "Shadowrocket", "WindowServer", "Microsoft Word", "Microsoft Excel", "Pages", "Numbers", "Keynote", "Xcode", "Visual Studio Code", "TextEdit", "Obsidian"]
for name in excludedNames {
    check(recommendedResourceCandidates([recommendation(name)], memoryFirst: false, now: fixtureNow).isEmpty, "bulk selection excludes terminal/system/network/document app: \(name)")
}
var systemRecommendation = recommendation("SystemTool")
systemRecommendation["path"] = "/System/Applications/SystemTool.app"
check(recommendedResourceCandidates([systemRecommendation], memoryFirst: false, now: fixtureNow).isEmpty, "system app paths never enter bulk selection")
var protectedRecommendation = browserRecommendation; protectedRecommendation["kind"] = "protected"
var inputRecommendation = browserRecommendation; inputRecommendation["kind"] = "input_restart"
var pauseRecommendation = browserRecommendation; pauseRecommendation["kind"] = "job_pause"
check(recommendedResourceCandidates([protectedRecommendation, inputRecommendation, pauseRecommendation], memoryFirst: false, now: fixtureNow).isEmpty, "manual input-method/job actions are not bulk recommendations")
var terminalRecommendation = browserRecommendation; terminalRecommendation["terminal_protected"] = true
check(recommendedResourceCandidates([terminalRecommendation], memoryFirst: false, now: fixtureNow).isEmpty, "protected ancestry cannot enter a bulk selection")
var missingIdentity = browserRecommendation; missingIdentity["action_identity"] = NSNull()
check(recommendedResourceCandidates([missingIdentity], memoryFirst: false, now: fixtureNow).isEmpty, "bulk recommendation requires original instance identity")
let ranked = [recommendation("One", cpu: 31), recommendation("Two", cpu: 90), recommendation("Three", cpu: 55), recommendation("Four", cpu: 110), recommendation("Small", cpu: 29)]
let rankedResult = recommendedResourceCandidates(ranked, memoryFirst: false, now: fixtureNow)
check(rankedResult.map { URL(fileURLWithPath: $0["path"] as! String).lastPathComponent } == ["Four.app", "Two.app", "Three.app"], "CPU ranking picks at most three above-threshold applications")
let memoryRanked = [recommendation("LowCPU", cpu: 0, memory: 2048), recommendation("Medium", cpu: 90, memory: 1024), recommendation("Threshold", cpu: 5, memory: 512), recommendation("TooSmall", cpu: 200, memory: 511)]
let memoryResult = recommendedResourceCandidates(memoryRanked, memoryFirst: true, now: fixtureNow)
check(memoryResult.map { ($0["rss_mb_sum"] as! NSNumber).doubleValue } == [2048, 1024, 512], "memory selection ranks by RSS independently of CPU and includes the 512-MB boundary")
check((memoryResult[0]["recommendation_reason"] as? String)?.contains("2048 MB") == true, "memory recommendation explains RSS amount without claiming all pages will be freed")
check(recommendedResourceCandidates([recommendation("Threshold", cpu: 30)], memoryFirst: false, now: fixtureNow).count == 1, "CPU boundary is 30 percent of a single core")
check(recommendedResourceCandidates([browserRecommendation, browserRecommendation], memoryFirst: false, now: fixtureNow).count == 1, "repeated app rows are recommended only once")
check(recommendedResourceCandidates([], memoryFirst: false, now: fixtureNow).isEmpty && recommendedResourceCandidates([recommendation("Idle", cpu: 0, memory: 0)], memoryFirst: false, now: fixtureNow).isEmpty, "no eligible app leaves the recommendation empty")
check(browserRecommendation["recommendation_selected"] == nil, "pure selection does not mutate the original candidates or perform an action")

if let index = CommandLine.arguments.firstIndex(of: "--integration-fixture"), index + 1 < CommandLine.arguments.count {
    let fixtureBinary = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SamplingActionFixture-\(UUID().uuidString)").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func runFixture(refuse: Bool) throws {
        let caseDirectory = directory.appendingPathComponent(refuse ? "refuse" : "accept")
        let bundle = caseDirectory.appendingPathComponent("SamplingFixture.app")
        let executableDirectory = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixtureBinary, to: executableDirectory.appendingPathComponent("SamplingFixture"))
        let info: [String: Any] = ["CFBundleIdentifier": "test.tianli.samplingfixture.\(UUID().uuidString)",
                                  "CFBundleName": "SamplingFixture", "CFBundleExecutable": "SamplingFixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        if refuse { try Data().write(to: caseDirectory.appendingPathComponent("refuse")) }
        let options = NSWorkspace.OpenConfiguration()
        options.activates = false; options.hides = true; options.addsToRecentItems = false
        options.createsNewApplicationInstance = true; options.arguments = [caseDirectory.path]
        var opened: NSRunningApplication?; var launchError: Error?; var completed = false
        NSWorkspace.shared.openApplication(at: bundle, configuration: options) { app, error in
            opened = app; launchError = error; completed = true
        }
        let launchDeadline = Date().addingTimeInterval(5)
        while !completed && Date() < launchDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        if let error = launchError { throw error }
        guard let opened = opened else { fatalError("fixture launch did not complete") }
        // Fixture exits itself after 20 seconds if the test is interrupted.
        let readyDeadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: caseDirectory.appendingPathComponent("ready").path) && Date() < readyDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        check(!opened.isTerminated && opened.activationPolicy == .regular, "owned fixture runs as a regular app without a window")
        let actual = collectProcesses()
        var liveSnapshot = processReport(previous: actual, current: actual, logicalCores: ProcessInfo.processInfo.activeProcessorCount)
        liveSnapshot["time"] = ISO8601DateFormatter().string(from: Date())
        // Restrict the test UI data to the app the test just created; no user app
        // can enter this dispatch path even if it is using more CPU or memory.
        let group = (liveSnapshot["top"] as! [[String: Any]]).first { ($0["pids"] as? [Int])?.contains(Int(opened.processIdentifier)) == true }
            ?? {
                let one = sample([actual.rows[Int(opened.processIdentifier)]!])
                return (processReport(previous: one, current: one, logicalCores: 1)["top"] as! [[String: Any]])[0]
            }()
        liveSnapshot["top"] = [group]
        let ownedCandidate = resourceCandidates(snapshot: liveSnapshot, memoryFirst: false).first!
        if ownedCandidate["kind"] as? String != "app_quit" {
            print("FIXTURE CANDIDATE", ownedCandidate)
            print("FIXTURE GROUP", group)
            print("FIXTURE APP", opened.bundleURL?.path ?? "missing", opened.processIdentifier)
            if let process = actual.rows[Int(opened.processIdentifier)] { print("FIXTURE CHAIN", ancestors(of: process, in: actual.rows).map { [$0.pid.description, $0.path] }) }
            fflush(stdout)
        }
        check(ownedCandidate["pid"] as? Int == Int(opened.processIdentifier) && ownedCandidate["kind"] as? String == "app_quit", "real fixture candidate uses the original sampled app identity")
        let response = performResourceAction(ownedCandidate)
        check(FileManager.default.fileExists(atPath: caseDirectory.appendingPathComponent("quit-request").path), "normal terminate request reaches fixture's applicationShouldTerminate")
        if refuse {
            check(response["outcome"] as? String == "still_running_or_awaiting_save" && !opened.isTerminated, "fixture refusal is respected without force termination")
            try FileManager.default.removeItem(at: caseDirectory.appendingPathComponent("refuse"))
            _ = opened.terminate()
        } else {
            check(response["outcome"] as? String == "original_process_exited", "accepted normal quit is observed as original instance exit")
        }
        let exitDeadline = Date().addingTimeInterval(3)
        while !opened.isTerminated && Date() < exitDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        check(opened.isTerminated, "owned fixture was cleaned up using normal quit")
    }
    try runFixture(refuse: false)
    try runFixture(refuse: true)
}
print("PASS: \(passed) safe action identity and eligibility checks")
