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

let fastGate = AutomaticCPUGate()
for time in 0..<5 { check(!fastGate.observe(now: Double(time), cpu: 96), "less than five complete high CPU seconds cannot qualify") }
check(!fastGate.ready(at: 5), "ready cannot infer a fifth second without its observation")
check(fastGate.observe(now: 5, cpu: 96), "strictly above 95 for five seconds qualifies")
check(fastGate.ready(at: 6.5) && !fastGate.ready(at: 6.5001), "qualification expires after 1.5 seconds without a new observation")
check(!fastGate.ready(at: 4) && !fastGate.ready(at: .nan), "backwards or invalid query clocks cannot reuse qualification")

let exactly95 = AutomaticCPUGate(config: ["prompt_cpu_threshold": 80])
for time in 0...8 { check(!exactly95.observe(now: Double(time), cpu: 95), "CPU exactly 95 never qualifies, even with a lower legacy threshold") }
let fastDip = AutomaticCPUGate()
for time in 0...4 { _ = fastDip.observe(now: Double(time), cpu: 99) }
check(!fastDip.observe(now: 5, cpu: 95), "equality resets an almost-complete high CPU streak")
for time in 6...10 { check(!fastDip.observe(now: Double(time), cpu: 99), "five fresh seconds are required after equality") }
check(fastDip.observe(now: 11, cpu: 99), "fresh post-dip streak qualifies")

let fastGap = AutomaticCPUGate()
for time in 0...4 { _ = fastGap.observe(now: Double(time), cpu: 96) }
check(!fastGap.observe(now: 6, cpu: 96), "a missed one-second reading resets qualification")
for time in 7...10 { check(!fastGap.observe(now: Double(time), cpu: 96), "post-gap samples cannot inherit the earlier streak") }
check(fastGap.observe(now: 11, cpu: 96), "five fresh seconds after the gap qualify")
check(!fastGap.observe(now: 11, cpu: 96) && !fastGap.ready(at: 11), "duplicate timestamps reset the gate")
for time in 12...17 { _ = fastGap.observe(now: Double(time), cpu: 96) }
check(!fastGap.observe(now: 16, cpu: 96) && !fastGap.ready(at: 17), "out-of-order timestamps reset prior qualification")

let fastInvalid = AutomaticCPUGate()
for time in 0...5 { _ = fastInvalid.observe(now: Double(time), cpu: 96) }
check(!fastInvalid.observe(now: 6, cpu: .nan) && !fastInvalid.ready(at: 6), "invalid CPU immediately invalidates qualification")
for time in 7...12 { _ = fastInvalid.observe(now: Double(time), cpu: 96) }
check(!fastInvalid.observe(now: .nan, cpu: 99) && !fastInvalid.ready(at: 12), "invalid observation time resets qualification")
check(!AutomaticCPUGate().observe(now: 0, cpu: 101), "out-of-range host CPU is not evidence")

let fastPolicy = IncidentPolicy()
let instant = fastPolicy.evaluate(signal(5, cpu: 80), automaticCPUQualified: fastGate.ready(at: 5))
check(instant.shouldPrompt && instant.shouldRecord && instant.reasons.contains("cpu_critical"),
      "a qualified five-second gate immediately opens an incident despite an 80 percent long-window average")
check(!fastPolicy.evaluate(signal(6, cpu: 80), automaticCPUQualified: true).shouldPrompt,
      "qualified pulses cannot create overlapping pending prompts")
fastPolicy.promptPresented(at: 6)
check(!fastPolicy.evaluate(signal(7, cpu: 80), automaticCPUQualified: true).shouldPrompt,
      "the fast gate retains existing prompt cooldown")
check(!fastPolicy.evaluate(signal(8, cpu: 99), automaticCPUQualified: false).shouldPrompt,
      "an explicit false pulse result cannot be overridden by a high long-window average")

let fastOtherReasons = IncidentPolicy()
for time in [0, 15, 30] { _ = fastOtherReasons.evaluate(signal(Double(time), cpu: 80, pressure: 4), automaticCPUQualified: false) }
let silentCritical = fastOtherReasons.evaluate(signal(45, cpu: 80, pressure: 4), automaticCPUQualified: false)
check(silentCritical.shouldRecord && silentCritical.reasons.contains("memory_critical") && !silentCritical.shouldPrompt,
      "other critical metrics still record incidents while the fast CPU gate is false")
let restoredFastCooldown = IncidentPolicy(config: ["last_prompt_at": 0, "last_prompt_severity": "critical"])
let fastHeld = restoredFastCooldown.evaluate(signal(5, cpu: 80), automaticCPUQualified: true)
check(fastHeld.shouldRecord && !fastHeld.shouldPrompt, "restored cooldown suppresses a fast prompt without losing its event")
let fastRecovery = IncidentPolicy()
_ = fastRecovery.evaluate(signal(5, cpu: 80), automaticCPUQualified: true)
for time in [20, 35, 50, 65] { _ = fastRecovery.evaluate(signal(Double(time)), automaticCPUQualified: false) }
check(!fastRecovery.evaluate(signal(80), automaticCPUQualified: true).recovered,
      "fresh one-second overload prevents a low long-window average from declaring recovery")

let sparseDefaults = IncidentPolicy()
check(!feed(sparseDefaults, through: 120, cpu: 99).shouldPrompt,
      "15-second diagnostic averages alone cannot establish today's five-second gate")
let denseDefaults = IncidentPolicy()
for time in 0..<5 { check(!denseDefaults.evaluate(signal(Double(time), cpu: 96)).shouldPrompt, "default fallback waits for five actual seconds") }
check(denseDefaults.evaluate(signal(5, cpu: 96)).shouldPrompt, "default policy fallback uses strict five-second sampling")

// Prior 15-second/60-second fixtures remain explicit compatibility checks.
// New production defaults are tested separately at a one-second cadence below.
func legacyPolicy(config: [String: Any] = [:]) -> IncidentPolicy {
    var settings: [String: Any] = ["prompt_sustained_seconds": 60, "prompt_cpu_interval_seconds": 15]
    settings.merge(config) { _, new in new }
    return IncidentPolicy(config: settings)
}

let brief = legacyPolicy()
check(!feed(brief, through: 45, cpu: 96).shouldPrompt, "less than a complete severe CPU window must not alert")
let full = brief.evaluate(signal(60, cpu: 96))
check(full.shouldPrompt && full.shouldRecord && full.severity == "critical", "severe CPU after 60 seconds opens an incident")
check(!brief.evaluate(signal(75, cpu: 96)).shouldPrompt, "an unacknowledged prompt stays pending")
brief.promptPresented(at: 76)
check(!brief.evaluate(signal(90, cpu: 96)).shouldPrompt, "presentation starts the user cooldown")

let tolerance = legacyPolicy()
var toleranceResult = tolerance.evaluate(signal(0, cpu: 80))
for time in stride(from: 15, through: 120, by: 15) {
    toleranceResult = tolerance.evaluate(signal(Double(time), cpu: time == 60 ? 55 : 80))
}
check(toleranceResult.reasons.contains("cpu_sustained") && toleranceResult.shouldRecord && !toleranceResult.shouldPrompt,
      "moderate CPU keeps tolerant event recording without automatic interruption")
let insufficient = legacyPolicy()
var insufficientResult = insufficient.evaluate(signal(0, cpu: 80))
for time in stride(from: 15, through: 120, by: 15) {
    insufficientResult = insufficient.evaluate(signal(Double(time), cpu: [30, 60].contains(time) ? 55 : 80))
}
check(!insufficientResult.shouldPrompt, "75 percent of a window does not meet the 80 percent rule")

let gap = legacyPolicy()
_ = feed(gap, through: 45, cpu: 96)
check(!gap.evaluate(signal(300, cpu: 96)).shouldPrompt, "sleep or collection gap cannot count toward sustained load")
check(!gap.evaluate(signal(300, cpu: 96)).shouldRecord, "duplicate timestamps are not additional evidence")
check(!gap.evaluate(signal(299, cpu: 96)).shouldRecord, "out-of-order timestamps cannot create evidence")
for time in [315, 330, 345] { _ = gap.evaluate(signal(Double(time), cpu: 96)) }
check(!gap.evaluate(signal(360, cpu: 96)).shouldPrompt, "out-of-order evidence also resets the legacy fallback gate")
check(gap.evaluate(signal(375, cpu: 96)).shouldPrompt, "a full fresh window after the ordering reset alerts normally")

let window = legacyPolicy()
let windowResult = feed(window, through: 120, cpu: 35, window: 200)
check(windowResult.reasons.contains("windowserver_sustained") && windowResult.shouldRecord && !windowResult.shouldPrompt,
      "WindowServer below the host CPU prompt threshold is recorded silently")
let process = legacyPolicy()
let processResult = feed(process, through: 180, cpu: 15, process: 100)
check(processResult.reasons.contains("process_sustained") && processResult.severity == "warning" && !processResult.shouldPrompt,
      "a sustained core-consuming process produces recorded recommendations without a prompt")
let changingProcess = legacyPolicy()
var changingResult = changingProcess.evaluate(signal(0, process: 100, identity: "pid-1/start-1"))
for time in stride(from: 15, through: 300, by: 15) {
    changingResult = changingProcess.evaluate(signal(Double(time), process: 100, identity: time % 30 == 0 ? "pid-1/start-1" : "pid-2/start-2"))
}
check(!changingResult.reasons.contains("process_sustained"), "rotating high CPU PIDs are not one sustained process")
let missingProcess = legacyPolicy()
var missingResult = missingProcess.evaluate(signal(0, process: 100, identity: nil))
for time in stride(from: 15, through: 300, by: 15) {
    missingResult = missingProcess.evaluate(signal(Double(time), process: 100, identity: nil))
}
check(!missingResult.reasons.contains("process_sustained"), "missing or unmeasured process identity cannot establish a sustained process")
let reusedProcess = legacyPolicy()
_ = reusedProcess.evaluate(signal(0, process: 100, identity: "pid-1/start-1"))
for time in stride(from: 15, through: 165, by: 15) {
    _ = reusedProcess.evaluate(signal(Double(time), process: 100, identity: "pid-1/start-1"))
}
check(!reusedProcess.evaluate(signal(180, process: 100, identity: "pid-1/start-2")).reasons.contains("process_sustained"),
      "PID reuse cannot inherit the previous instance's sustained window")

let quietWarning = legacyPolicy()
check(!feed(quietWarning, through: 300, cpu: 30, pressure: 2).shouldPrompt,
      "warning pressure alone with no CPU or swap activity is insufficient")
let swapping = legacyPolicy()
check(feed(swapping, through: 180, cpu: 30, pressure: 2, input: 1.5).reasons.contains("memory_warning"),
      "warning pressure with active paging alerts")
let memoryCPU = legacyPolicy()
check(feed(memoryCPU, through: 180, cpu: 65, pressure: 2).reasons.contains("memory_warning"),
      "warning pressure with CPU load alerts before critical pressure")
let memoryCritical = legacyPolicy()
let memoryCriticalResult = feed(memoryCritical, through: 45, pressure: 4)
check(memoryCriticalResult.reasons.contains("memory_critical") && memoryCriticalResult.severity == "critical",
      "critical memory pressure independently alerts after 45 seconds")
check(memoryCriticalResult.shouldRecord && !memoryCriticalResult.shouldPrompt,
      "critical memory pressure alone records evidence without a prompt")
let heat = legacyPolicy()
check(feed(heat, through: 120, thermal: 2).reasons.contains("thermal_serious"), "serious thermal pressure is covered")
let criticalHeat = legacyPolicy()
check(feed(criticalHeat, through: 60, thermal: 3).severity == "critical", "critical thermal pressure escalates")
check(!criticalHeat.evaluate(signal(75, thermal: 3)).shouldPrompt, "critical thermal pressure alone cannot prompt")

let belowPromptThreshold = legacyPolicy(config: ["cpu_threshold": 90, "window_match_ratio": 0.5, "prompt_cpu_threshold": 80])
let belowPromptResult = feed(belowPromptThreshold, through: 300, cpu: 94.99, pressure: 4, thermal: 3)
check(belowPromptResult.reasons.contains("cpu_critical") && !belowPromptResult.shouldPrompt,
      "CPU below 95 cannot prompt even with critical reasons or old/tolerant config")
let strictDip = legacyPolicy()
_ = feed(strictDip, through: 30, cpu: 96)
_ = strictDip.evaluate(signal(45, cpu: 94.99))
for time in [60, 75, 90, 105] {
    check(!strictDip.evaluate(signal(Double(time), cpu: 96)).shouldPrompt,
          "a single CPU dip resets the full automatic prompt window")
}
check(strictDip.evaluate(signal(120, cpu: 96)).shouldPrompt, "exactly 60 fresh seconds after a dip permits a prompt")
let missedSample = legacyPolicy()
_ = feed(missedSample, through: 30, cpu: 96)
for time in [60, 75, 90, 105] {
    check(!missedSample.evaluate(signal(Double(time), cpu: 96)).shouldPrompt,
          "a missing scheduled sample resets automatic prompt continuity")
}
check(missedSample.evaluate(signal(120, cpu: 96)).shouldPrompt, "a complete fresh window after a missed sample permits a prompt")
let invalidCPU = legacyPolicy()
_ = feed(invalidCPU, through: 30, cpu: 96)
check(!invalidCPU.evaluate(signal(45, cpu: .nan)).shouldPrompt, "invalid CPU resets continuity")
for time in [60, 75, 90, 105] { check(!invalidCPU.evaluate(signal(Double(time), cpu: 96)).shouldPrompt, "invalid CPU cannot fill the strict window") }
check(invalidCPU.evaluate(signal(120, cpu: 96)).shouldPrompt, "fresh valid CPU window can prompt again")

let retry = legacyPolicy()
check(feed(retry, through: 60, cpu: 96).shouldPrompt, "initial prompt dispatch")
retry.promptFailed(at: 61)
check(!retry.evaluate(signal(75, cpu: 96)).shouldPrompt, "failed prompt has a short retry delay")
check(!retry.evaluate(signal(90, cpu: 96)).shouldPrompt, "retry delay uses time, not the next sample")
check(retry.evaluate(signal(105, cpu: 96)).shouldPrompt, "failed prompt retries without a 30 minute cooldown")
retry.promptPresented(at: 106)
let continued = retry.evaluate(signal(120, cpu: 96))
check(continued.shouldRecord && !continued.shouldPrompt, "recording proceeds independently during prompt cooldown")

let escalation = legacyPolicy()
check(!feed(escalation, through: 120, cpu: 80).shouldPrompt, "moderate CPU is silent before manual inspection")
escalation.promptPresented(at: 121, severity: "warning") // A manually opened warning can still acknowledge presentation.
for time in [135, 150, 165, 180] {
    check(!escalation.evaluate(signal(Double(time), cpu: 96)).shouldPrompt, "severity upgrade cannot bypass strict CPU duration")
}
let escalated = escalation.evaluate(signal(195, cpu: 96))
check(escalated.severity == "critical" && escalated.shouldPrompt,
      "severity upgrade bypasses prior warning cooldown only after the strict CPU gate")
escalation.promptPresented(at: 196)
for time in [210, 225, 240, 255] {
    check(!escalation.evaluate(signal(Double(time))).recovered, "recovery requires 60 complete low-load seconds")
}
let recovered = escalation.evaluate(signal(270))
check(recovered.recovered && recovered.shouldRecord && recovered.reasons.isEmpty, "sustained low load resolves and records the incident")
check(!escalation.evaluate(signal(285, cpu: 96)).shouldRecord, "cleared evidence cannot immediately reopen on one high sample")

let warningRecovery = legacyPolicy()
_ = feed(warningRecovery, through: 60, cpu: 96, pressure: 2)
warningRecovery.promptPresented(at: 61)
for time in [75, 90, 105, 120] { _ = warningRecovery.evaluate(signal(Double(time), pressure: 2)) }
check(warningRecovery.evaluate(signal(135, pressure: 2)).recovered,
      "stable warning without CPU or paging activity clears the overload combination")
let unknownRecovery = legacyPolicy()
_ = feed(unknownRecovery, through: 60, cpu: 96)
for time in [75, 90, 105, 120] { _ = unknownRecovery.evaluate(signal(Double(time), pressure: 0)) }
check(!unknownRecovery.evaluate(signal(135, pressure: 0)).recovered, "unknown memory pressure cannot prove overload recovery")

let delayedAcknowledgement = legacyPolicy()
check(feed(delayedAcknowledgement, through: 60, cpu: 96).shouldPrompt, "qualified high CPU prompt is pending")
for time in [75, 90, 105] { _ = delayedAcknowledgement.evaluate(signal(Double(time), cpu: 96, pressure: 4)) }
let unacknowledgedUpgrade = delayedAcknowledgement.evaluate(signal(120, cpu: 96, pressure: 4))
check(unacknowledgedUpgrade.severity == "critical" && !unacknowledgedUpgrade.shouldPrompt,
      "additional critical reasons cannot create overlapping prompt dispatch")
delayedAcknowledgement.promptPresented(at: 121, severity: "critical")
check(!delayedAcknowledgement.evaluate(signal(135, cpu: 96)).shouldPrompt,
      "acknowledged critical prompt observes cooldown")

let stalePrompt = legacyPolicy()
check(feed(stalePrompt, through: 60, cpu: 96).shouldPrompt, "prepare pending stale prompt")
stalePrompt.promptFailed(at: 61)
check(!stalePrompt.evaluate(signal(75)).shouldPrompt, "falling load does not prompt from old sustained evidence")
check(!stalePrompt.evaluate(signal(105)).shouldPrompt, "expired retry with normal current sample does not resurrect a prompt")

let overridden = legacyPolicy(config: ["moderate_cpu_threshold": 50, "moderate_sustained_seconds": 30])
check(feed(overridden, through: 30, cpu: 55).reasons.contains("cpu_sustained"), "thresholds and durations are configurable")
let historicalCooldown = legacyPolicy(config: ["last_prompt_at": 0, "last_prompt_severity": "critical"])
let held = feed(historicalCooldown, through: 60, cpu: 96)
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
let replay = legacyPolicy()
var firstPrompt: Int?
var firstRecorded: Int?
var oldHighSince: Int?
var oldPrompt: Int?
for (index, observation) in history.enumerated() {
    let time = index * 15
    let result = replay.evaluate(signal(Double(time), cpu: observation.0, pressure: observation.1))
    if result.shouldRecord && firstRecorded == nil { firstRecorded = time }
    if result.shouldPrompt && firstPrompt == nil { firstPrompt = time; replay.promptPresented(at: Double(time)) }
    if observation.0 >= 90 || observation.1 == 4 {
        if oldHighSince == nil { oldHighSince = time }
    } else { oldHighSince = nil }
    if let since = oldHighSince, time - since >= 60 && oldPrompt == nil { oldPrompt = time }
}
check(firstRecorded == 150 && firstPrompt == 285,
      "legacy 60-second fixture preserves historical evidence and strict-threshold prompt timing")
check(oldPrompt == 285 && firstPrompt == oldPrompt,
      "sparse historical samples validate the explicit legacy configuration, not today's one-second gate")

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
let fastAnalysis = incidentAnalysis(snapshot: ["cpu_percent": 80, "prompt_cpu_qualified": true,
    "prompt_cpu_percent": 97.5, "prompt_cpu_threshold": 95, "prompt_sustained_seconds": 5], reasons: ["cpu_critical"])
let fastFacts = (fastAnalysis["facts"] as! [String]).joined()
check(fastFacts.contains("连续 5 秒严格大于 95.0%") && fastFacts.contains("97.5%") && fastFacts.contains("时间范围不同"),
      "advice explains why the five-second trigger differs from the lower diagnostic average")
print("PASS: \(passed) incident policy, historical replay and analysis checks")
