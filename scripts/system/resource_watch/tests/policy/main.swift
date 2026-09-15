import Foundation

var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    passed += 1
}
func signal(_ time: Double, cpu: Double = 10, pressure: Int = 1, input: Double = 0,
            output: Double = 0, window: Double = 0, process: Double = 0, thermal: Int = 0,
            identity: String? = "test-pid/start-microseconds") -> IncidentSignal {
    IncidentSignal(now: time, cpu: cpu, pressure: pressure, swapInMBps: input, swapOutMBps: output,
                   windowServerCPU: window, topProcessCPU: process, thermal: thermal, topProcessID: identity)
}
func feed(_ policy: IncidentPolicy, through end: Int, cpu: Double = 10, pressure: Int = 1,
          input: Double = 0, window: Double = 0, process: Double = 0, thermal: Int = 0) -> IncidentDecision {
    var result = policy.evaluate(signal(0, cpu: cpu, pressure: pressure, input: input, window: window, process: process, thermal: thermal))
    if end >= 15 {
        for time in stride(from: 15, through: end, by: 15) {
            result = policy.evaluate(signal(Double(time), cpu: cpu, pressure: pressure, input: input, window: window, process: process, thermal: thermal))
        }
    }
    return result
}

let brief = IncidentPolicy()
check(!feed(brief, through: 45, cpu: 95).shouldPrompt, "less than a complete severe CPU window must not alert")
let full = brief.evaluate(signal(60, cpu: 95))
check(full.shouldPrompt && full.shouldRecord && full.severity == "critical", "severe CPU after 60 seconds opens an incident")
check(!brief.evaluate(signal(75, cpu: 95)).shouldPrompt, "an unacknowledged prompt stays pending")
brief.promptPresented(at: 76)
check(!brief.evaluate(signal(90, cpu: 95)).shouldPrompt, "presentation starts the user cooldown")

let tolerance = IncidentPolicy()
var toleranceResult = tolerance.evaluate(signal(0, cpu: 80))
for time in stride(from: 15, through: 120, by: 15) {
    toleranceResult = tolerance.evaluate(signal(Double(time), cpu: time == 60 ? 55 : 80))
}
check(toleranceResult.reasons.contains("cpu_sustained") && toleranceResult.shouldPrompt,
      "one low point among eight intervals does not erase sustained moderate CPU")
let insufficient = IncidentPolicy()
var insufficientResult = insufficient.evaluate(signal(0, cpu: 80))
for time in stride(from: 15, through: 120, by: 15) {
    insufficientResult = insufficient.evaluate(signal(Double(time), cpu: [30, 60].contains(time) ? 55 : 80))
}
check(!insufficientResult.shouldPrompt, "75 percent of a window does not meet the 80 percent rule")

let gap = IncidentPolicy()
_ = feed(gap, through: 45, cpu: 95)
check(!gap.evaluate(signal(300, cpu: 95)).shouldPrompt, "sleep or collection gap cannot count toward sustained load")
check(!gap.evaluate(signal(300, cpu: 95)).shouldRecord, "duplicate timestamps are not additional evidence")
check(!gap.evaluate(signal(299, cpu: 95)).shouldRecord, "out-of-order timestamps cannot create evidence")
for time in [315, 330, 345] { _ = gap.evaluate(signal(Double(time), cpu: 95)) }
check(gap.evaluate(signal(360, cpu: 95)).shouldPrompt, "a full fresh window after resume alerts normally")

let window = IncidentPolicy()
let windowResult = feed(window, through: 120, cpu: 35, window: 200)
check(windowResult.reasons.contains("windowserver_sustained") && windowResult.shouldPrompt,
      "WindowServer alerts below the host CPU threshold")
let process = IncidentPolicy()
let processResult = feed(process, through: 180, cpu: 15, process: 100)
check(processResult.reasons.contains("process_sustained") && processResult.severity == "warning" && processResult.shouldPrompt,
      "a sustained core-consuming process produces a recommendation prompt")
let changingProcess = IncidentPolicy()
var changingResult = changingProcess.evaluate(signal(0, process: 100, identity: "pid-1/start-1"))
for time in stride(from: 15, through: 300, by: 15) {
    changingResult = changingProcess.evaluate(signal(Double(time), process: 100, identity: time % 30 == 0 ? "pid-1/start-1" : "pid-2/start-2"))
}
check(!changingResult.reasons.contains("process_sustained"), "rotating high CPU PIDs are not one sustained process")
let missingProcess = IncidentPolicy()
var missingResult = missingProcess.evaluate(signal(0, process: 100, identity: nil))
for time in stride(from: 15, through: 300, by: 15) {
    missingResult = missingProcess.evaluate(signal(Double(time), process: 100, identity: nil))
}
check(!missingResult.reasons.contains("process_sustained"), "missing or unmeasured process identity cannot establish a sustained process")
let reusedProcess = IncidentPolicy()
_ = reusedProcess.evaluate(signal(0, process: 100, identity: "pid-1/start-1"))
for time in stride(from: 15, through: 165, by: 15) {
    _ = reusedProcess.evaluate(signal(Double(time), process: 100, identity: "pid-1/start-1"))
}
check(!reusedProcess.evaluate(signal(180, process: 100, identity: "pid-1/start-2")).reasons.contains("process_sustained"),
      "PID reuse cannot inherit the previous instance's sustained window")

let quietWarning = IncidentPolicy()
check(!feed(quietWarning, through: 300, cpu: 30, pressure: 2).shouldPrompt,
      "warning pressure alone with no CPU or swap activity is insufficient")
let swapping = IncidentPolicy()
check(feed(swapping, through: 180, cpu: 30, pressure: 2, input: 1.5).reasons.contains("memory_warning"),
      "warning pressure with active paging alerts")
let memoryCPU = IncidentPolicy()
check(feed(memoryCPU, through: 180, cpu: 65, pressure: 2).reasons.contains("memory_warning"),
      "warning pressure with CPU load alerts before critical pressure")
let memoryCritical = IncidentPolicy()
let memoryCriticalResult = feed(memoryCritical, through: 45, pressure: 4)
check(memoryCriticalResult.reasons.contains("memory_critical") && memoryCriticalResult.severity == "critical",
      "critical memory pressure independently alerts after 45 seconds")
let heat = IncidentPolicy()
check(feed(heat, through: 120, thermal: 2).reasons.contains("thermal_serious"), "serious thermal pressure is covered")
let criticalHeat = IncidentPolicy()
check(feed(criticalHeat, through: 60, thermal: 3).severity == "critical", "critical thermal pressure escalates")

let retry = IncidentPolicy()
check(feed(retry, through: 60, cpu: 95).shouldPrompt, "initial prompt dispatch")
retry.promptFailed(at: 61)
check(!retry.evaluate(signal(75, cpu: 95)).shouldPrompt, "failed prompt has a short retry delay")
check(!retry.evaluate(signal(90, cpu: 95)).shouldPrompt, "retry delay uses time, not the next sample")
check(retry.evaluate(signal(105, cpu: 95)).shouldPrompt, "failed prompt retries without a 30 minute cooldown")
retry.promptPresented(at: 106)
let continued = retry.evaluate(signal(120, cpu: 95))
check(continued.shouldRecord && !continued.shouldPrompt, "recording proceeds independently during prompt cooldown")

let escalation = IncidentPolicy()
check(feed(escalation, through: 120, cpu: 80).shouldPrompt, "moderate CPU first presents warning")
escalation.promptPresented(at: 121)
for time in [135, 150, 165] { _ = escalation.evaluate(signal(Double(time), cpu: 95)) }
let escalated = escalation.evaluate(signal(180, cpu: 95))
check(escalated.severity == "critical" && escalated.shouldPrompt && escalated.shouldRecord,
      "severity upgrade bypasses prior warning cooldown")
escalation.promptPresented(at: 181)
for time in [195, 210, 225, 240] {
    check(!escalation.evaluate(signal(Double(time))).recovered, "recovery requires 60 complete low-load seconds")
}
let recovered = escalation.evaluate(signal(255))
check(recovered.recovered && recovered.shouldRecord && recovered.reasons.isEmpty, "sustained low load resolves and records the incident")
check(!escalation.evaluate(signal(270, cpu: 95)).shouldRecord, "cleared evidence cannot immediately reopen on one high sample")

let warningRecovery = IncidentPolicy()
_ = feed(warningRecovery, through: 60, cpu: 95, pressure: 2)
warningRecovery.promptPresented(at: 61)
for time in [75, 90, 105, 120] { _ = warningRecovery.evaluate(signal(Double(time), pressure: 2)) }
check(warningRecovery.evaluate(signal(135, pressure: 2)).recovered,
      "stable warning without CPU or paging activity clears the overload combination")
let unknownRecovery = IncidentPolicy()
_ = feed(unknownRecovery, through: 60, cpu: 95)
for time in [75, 90, 105, 120] { _ = unknownRecovery.evaluate(signal(Double(time), pressure: 0)) }
check(!unknownRecovery.evaluate(signal(135, pressure: 0)).recovered, "unknown memory pressure cannot prove overload recovery")

let delayedAcknowledgement = IncidentPolicy()
check(feed(delayedAcknowledgement, through: 120, cpu: 80).shouldPrompt, "warning prompt is pending before escalation")
for time in [135, 150, 165] { _ = delayedAcknowledgement.evaluate(signal(Double(time), cpu: 95)) }
let unacknowledgedUpgrade = delayedAcknowledgement.evaluate(signal(180, cpu: 95))
check(unacknowledgedUpgrade.severity == "critical" && !unacknowledgedUpgrade.shouldPrompt,
      "unacknowledged warning prevents overlapping prompt dispatch")
delayedAcknowledgement.promptPresented(at: 181, severity: "warning")
check(delayedAcknowledgement.evaluate(signal(195, cpu: 95)).shouldPrompt,
      "explicit older warning acknowledgement still permits a critical upgrade")

let stalePrompt = IncidentPolicy()
check(feed(stalePrompt, through: 60, cpu: 95).shouldPrompt, "prepare pending stale prompt")
stalePrompt.promptFailed(at: 61)
check(!stalePrompt.evaluate(signal(75)).shouldPrompt, "falling load does not prompt from old sustained evidence")
check(!stalePrompt.evaluate(signal(105)).shouldPrompt, "expired retry with normal current sample does not resurrect a prompt")

let overridden = IncidentPolicy(config: ["moderate_cpu_threshold": 50, "moderate_sustained_seconds": 30])
check(feed(overridden, through: 30, cpu: 55).reasons.contains("cpu_sustained"), "thresholds and durations are configurable")
let historicalCooldown = IncidentPolicy(config: ["last_prompt_at": 0, "last_prompt_severity": "critical"])
let held = feed(historicalCooldown, through: 60, cpu: 95)
check(held.shouldRecord && !held.shouldPrompt, "restart can restore prompt cooldown without suppressing incident recording")

// Real host CPU/pressure excerpt from samples-2026-09-14.jsonl, 09:10:03Z onward.
// Old process data were ps pcpu groups, so this replay deliberately does NOT pass
// those values as modern per-PID interval measurements or infer process causality.
let history: [(Double, Int)] = [
    (70.31,2),(78.21,2),(69.60,2),(84.71,1),(92.86,2),(87.30,2),(74.94,1),(87.54,2),
    (84.73,2),(81.93,2),(81.08,1),(70.84,1),(68.36,1),(80.64,1),(80.05,1),(95.36,1),
    (97.52,1),(99.98,2),(99.60,2),(98.11,2),(93.90,2),(88.46,2),(94.36,2),(77.32,2),
    (72.29,2),(63.64,2),(63.64,2),(62.23,2),(64.72,2),(86.63,2),(97.64,2),(95.37,2)
]
let replay = IncidentPolicy()
var firstPrompt: Int?
var oldHighSince: Int?
var oldPrompt: Int?
for (index, observation) in history.enumerated() {
    let time = index * 15
    let result = replay.evaluate(signal(Double(time), cpu: observation.0, pressure: observation.1))
    if result.shouldPrompt && firstPrompt == nil { firstPrompt = time; replay.promptPresented(at: Double(time)) }
    if observation.0 >= 90 || observation.1 == 4 {
        if oldHighSince == nil { oldHighSince = time }
    } else { oldHighSince = nil }
    if let since = oldHighSince, time - since >= 60 && oldPrompt == nil { oldPrompt = time }
}
check(firstPrompt == 150, "actual historical host/pressure replay first alerts at 17:12:33 Shanghai")
check(oldPrompt == 285 && firstPrompt! < oldPrompt!, "legacy continuous-90 rule first alerts at 17:14:48, 135 seconds later")

let analysis = incidentAnalysis(snapshot: ["cpu_percent": 65, "logical_cores": 10, "memory_pressure": 2,
    "swap_used_mb": 12000, "swap_in_mbps": 0.0, "swap_out_mbps": 0.0,
    "top": [["path": "/Applications/CPU Tool.app", "cpu_core_percent": 400]],
    "top_memory": [["path": "/Applications/Memory Tool.app", "rss_mb_sum": 8000]],
    "top_processes": [["terminal_protected": true]]], reasons: ["memory_warning", "windowserver_sustained"])
let factText = (analysis["facts"] as! [String]).joined()
let recommendationText = (analysis["recommendations"] as! [String]).joined()
check(factText.contains("存量") && factText.contains("速率") && factText.contains("一个核心"), "analysis distinguishes core/host units and swap stock/flow")
check(recommendationText.contains("Memory Tool.app") && !recommendationText.contains("CPU Tool.app"), "memory recommendations use memory ranking")
check((analysis["hypotheses"] as! [String]).joined().contains("未定位"), "WindowServer source stays an explicit unknown")
check(recommendationText.contains("不会自动结束"), "analysis preserves terminal tasks")
check(JSONSerialization.isValidJSONObject(analysis), "analysis is JSON serializable")
let noMemory = incidentAnalysis(snapshot: ["memory_pressure": 4], reasons: ["memory_critical"])
check((noMemory["recommendations"] as! [String]).joined().contains("缺少按内存排序"), "missing memory ranking stays unknown")
print("PASS: \(passed) incident policy, historical replay and analysis checks")
