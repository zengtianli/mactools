import Foundation

// CPU values for the host are 0...100; process values use 100 = one core.
// now is Unix time. Samples describe the interval ending at now.
struct IncidentSignal {
    let now: Double
    let cpu: Double
    let pressure: Int
    let swapInMBps: Double
    let swapOutMBps: Double
    let windowServerCPU: Double
    let topProcessCPU: Double
    let thermal: Int
    let topProcessID: String?
    init(now: Double, cpu: Double, pressure: Int, swapInMBps: Double, swapOutMBps: Double,
         windowServerCPU: Double, topProcessCPU: Double, thermal: Int, topProcessID: String? = nil) {
        self.now = now; self.cpu = cpu; self.pressure = pressure
        self.swapInMBps = swapInMBps; self.swapOutMBps = swapOutMBps
        self.windowServerCPU = windowServerCPU; self.topProcessCPU = topProcessCPU
        self.thermal = thermal; self.topProcessID = topProcessID
    }
}

struct IncidentDecision {
    let reasons: [String]
    let severity: String
    let shouldRecord: Bool
    let shouldPrompt: Bool
    let recovered: Bool
}

/// Lightweight host-CPU gate, independent of the 15-second diagnostic cadence.
/// Use one consistent clock for observe and ready (prefer monotonic uptime).
final class AutomaticCPUGate {
    private let threshold: Double
    private let sustainedSeconds: Double
    private let maxGap: Double
    private var lastObserved: Double?
    private var highSince: Double?

    init(config: [String: Any] = [:]) {
        func value(_ key: String, _ fallback: Double, minimum: Double) -> Double {
            guard let number = config[key] as? NSNumber, number.doubleValue.isFinite else { return fallback }
            return max(minimum, number.doubleValue)
        }
        threshold = min(100, value("prompt_cpu_threshold", 95, minimum: 95))
        sustainedSeconds = value("prompt_sustained_seconds", 5, minimum: 1)
        maxGap = value("prompt_cpu_interval_seconds", 1, minimum: 0.1) * 1.5
    }

    func reset() { lastObserved = nil; highSince = nil }

    @discardableResult
    func observe(now: Double, cpu: Double) -> Bool {
        guard now.isFinite else { reset(); return false }
        if let previous = lastObserved, now <= previous { reset(); return false }
        if let previous = lastObserved, now - previous > maxGap { highSince = nil }
        lastObserved = now
        guard cpu.isFinite && cpu > threshold && cpu <= 100 else { highSince = nil; return false }
        if highSince == nil { highSince = now }
        return ready(at: now)
    }

    func ready(at now: Double) -> Bool {
        guard now.isFinite, let last = lastObserved, let since = highSince,
              now >= last, now - last <= maxGap else { return false }
        // No extra duration is inferred between the last observation and now.
        return last - since >= sustainedSeconds
    }
}

/// Pure in-memory policy. It never launches a process or changes system state.
final class IncidentPolicy {
    private let config: [String: Any]
    private let fallbackCPUGate: AutomaticCPUGate
    private var samples: [IncidentSignal] = []
    private var activeReasons: [String] = []
    private var activeSeverity = "normal"
    private var recoverySince: Double?
    private var lastRecord: Double?
    private var recordedRank = 0
    private var lastPrompt: Double?
    private var presentedRank = 0
    private var pendingRank: Int?
    private var retryAfter = -Double.infinity

    init(config: [String: Any] = [:]) {
        self.config = config
        fallbackCPUGate = AutomaticCPUGate(config: config)
        if let value = config["last_prompt_at"] as? NSNumber, value.doubleValue.isFinite {
            lastPrompt = value.doubleValue
            presentedRank = Self.rank(config["last_prompt_severity"] as? String ?? "warning")
        }
    }

    private func number(_ key: String, _ fallback: Double, min minimum: Double = 0) -> Double {
        guard let value = config[key] as? NSNumber, value.doubleValue.isFinite else { return fallback }
        return max(minimum, value.doubleValue)
    }

    private static func rank(_ severity: String) -> Int {
        ["normal": 0, "advisory": 1, "warning": 2, "critical": 3][severity] ?? 0
    }

    private var windows: [Double] {
        [number("sustained_seconds", 60, min: 1), number("moderate_sustained_seconds", 120, min: 1),
         number("windowserver_sustained_seconds", 120, min: 1), number("process_sustained_seconds", 180, min: 1),
         number("memory_warning_seconds", 180, min: 1), number("memory_critical_seconds", 45, min: 1),
         number("thermal_sustained_seconds", 120, min: 1), number("thermal_critical_seconds", 60, min: 1)]
    }

    // Weight elapsed time, not sample count; a late sample cannot manufacture history.
    private func sustained(_ seconds: Double, _ matches: (IncidentSignal) -> Bool) -> Bool {
        guard let end = samples.last?.now, let first = samples.first?.now,
              samples.count > 1, end - first >= seconds else { return false }
        let start = end - seconds
        var covered = 0.0
        var matched = 0.0
        for index in 1..<samples.count {
            let sample = samples[index]
            let duration = max(0, sample.now - max(start, samples[index - 1].now))
            covered += duration
            if matches(sample) { matched += duration }
        }
        let ratio = min(1, number("window_match_ratio", 0.8, min: 0.5))
        // Also require the present sample to match, so a warning is not born after recovery.
        return covered >= seconds - 0.001 && matched >= seconds * ratio - 0.001 && matches(samples.last!)
    }

    func evaluate(_ signal: IncidentSignal, automaticCPUQualified: Bool? = nil) -> IncidentDecision {
        let empty = IncidentDecision(reasons: [], severity: "normal", shouldRecord: false, shouldPrompt: false, recovered: false)
        guard signal.now.isFinite else { fallbackCPUGate.reset(); return empty }
        // The caller normally supplies its fresh one-second gate. A standalone
        // policy can observe CPU itself, but sparse diagnostic samples never
        // manufacture five seconds of continuous one-second observations.
        let fallbackReady = automaticCPUQualified == nil ? fallbackCPUGate.observe(now: signal.now, cpu: signal.cpu) : false
        let promptCPUReady = automaticCPUQualified ?? fallbackReady
        let gapLimit = number("sample_gap_seconds", max(45, number("interval_seconds", 15, min: 5) * 3), min: 1)
        if let previous = samples.last, signal.now <= previous.now {
            // Ignore duplicate or out-of-order points; they are not new evidence.
            fallbackCPUGate.reset()
            return IncidentDecision(reasons: activeReasons, severity: activeSeverity, shouldRecord: false, shouldPrompt: false, recovered: false)
        }
        if let previous = samples.last, signal.now - previous.now > gapLimit {
            samples.removeAll()
            recoverySince = nil
        }
        samples.append(signal)
        let retention = max(windows.max() ?? 180, number("recovery_seconds", 60, min: 1))
        while samples.count > 2 && samples[1].now < signal.now - retention { samples.removeFirst() }

        let instantLow = !promptCPUReady && signal.cpu.isFinite && signal.cpu < number("recovery_cpu_threshold", 60)
            // A stable warning without CPU/paging load no longer meets the
            // overload combination. Unknown or critical pressure cannot recover.
            && [1, 2].contains(signal.pressure)
            && signal.windowServerCPU < number("recovery_windowserver_threshold", 100)
            && signal.topProcessCPU < number("recovery_process_threshold", 80)
            && signal.thermal < 2
            && signal.swapInMBps.isFinite && signal.swapOutMBps.isFinite
            && signal.swapInMBps + signal.swapOutMBps < number("recovery_swap_mbps", 1)
        if !activeReasons.isEmpty && instantLow {
            if recoverySince == nil { recoverySince = signal.now }
            if signal.now - recoverySince! >= number("recovery_seconds", 60, min: 1) {
                activeReasons = []; activeSeverity = "normal"; recoverySince = nil
                samples = [signal] // Prevent old high samples immediately reopening the incident.
                lastRecord = nil; recordedRank = 0
                return IncidentDecision(reasons: [], severity: "normal", shouldRecord: true, shouldPrompt: false, recovered: true)
            }
        } else { recoverySince = nil }

        var reasons: [String] = []
        if promptCPUReady || sustained(number("sustained_seconds", 60, min: 1), { $0.cpu >= self.number("cpu_threshold", 90) }) {
            reasons.append("cpu_critical")
        }
        if sustained(number("moderate_sustained_seconds", 120, min: 1), { $0.cpu >= self.number("moderate_cpu_threshold", 75) }) {
            reasons.append("cpu_sustained")
        }
        if sustained(number("windowserver_sustained_seconds", 120, min: 1), { $0.windowServerCPU >= self.number("windowserver_cpu_threshold", 150) }) {
            reasons.append("windowserver_sustained")
        }
        if let identity = signal.topProcessID, !identity.isEmpty,
           sustained(number("process_sustained_seconds", 180, min: 1), {
               $0.topProcessID == identity && $0.topProcessCPU >= self.number("process_cpu_threshold", 95)
           }) {
            reasons.append("process_sustained")
        }
        if sustained(number("memory_warning_seconds", 180, min: 1), {
            $0.pressure == 2 && ($0.cpu >= self.number("memory_warning_cpu_threshold", 60)
                || (max(0, $0.swapInMBps) + max(0, $0.swapOutMBps)) >= self.number("memory_warning_swap_mbps", 1))
        }) { reasons.append("memory_warning") }
        if sustained(number("memory_critical_seconds", 45, min: 1), { $0.pressure == 4 }) {
            reasons.append("memory_critical")
        }
        if sustained(number("thermal_sustained_seconds", 120, min: 1), { $0.thermal >= 2 }) {
            reasons.append("thermal_serious")
        }
        if sustained(number("thermal_critical_seconds", 60, min: 1), { $0.thermal >= 3 }) {
            reasons.append("thermal_critical")
        }

        let starting = activeReasons.isEmpty && !reasons.isEmpty
        if !reasons.isEmpty {
            activeReasons = reasons
            activeSeverity = reasons.contains(where: { ["cpu_critical", "memory_critical", "thermal_critical"].contains($0) }) ? "critical" : "warning"
        }
        guard !activeReasons.isEmpty else { return empty }
        let rank = Self.rank(activeSeverity)
        let shouldRecord = starting || rank > recordedRank || lastRecord == nil
            || signal.now - lastRecord! >= number("record_interval_seconds", 60, min: 1)
        if shouldRecord { lastRecord = signal.now; recordedRank = rank }
        // Dips retain the open incident, but do not trigger a new prompt on stale evidence.
        let shouldPrompt = promptCPUReady && !reasons.isEmpty && pendingRank == nil && signal.now >= retryAfter
            && (lastPrompt == nil || signal.now - lastPrompt! >= number("cooldown_seconds", 1800)
                || rank > presentedRank)
        if shouldPrompt { pendingRank = rank }
        return IncidentDecision(reasons: activeReasons, severity: activeSeverity,
                                shouldRecord: shouldRecord, shouldPrompt: shouldPrompt, recovered: false)
    }

    /// Call only after the prompt child acknowledges that its UI was presented.
    func promptPresented(at time: Double, severity: String? = nil) {
        guard time.isFinite else { return }
        lastPrompt = time
        // The acknowledged panel may show an older warning while sampling has
        // already escalated. Its frozen severity, not current load, sets cooldown.
        presentedRank = severity.map { Self.rank($0) } ?? pendingRank ?? Self.rank(activeSeverity)
        pendingRank = nil
        retryAfter = -Double.infinity
    }

    /// Launch, acknowledgement or display failure does not consume the user cooldown.
    func promptFailed(at time: Double) {
        guard time.isFinite else { return }
        pendingRank = nil
        retryAfter = time + number("prompt_retry_seconds", 30, min: 5)
    }
}

/// Human-readable local analysis. Facts describe observations; hypotheses do not
/// attribute WindowServer to a particular app or infer a hang from CPU alone.
func incidentAnalysis(snapshot: [String: Any], reasons: [String]) -> [String: Any] {
    func numeric(_ key: String) -> Double? {
        guard let number = snapshot[key] as? NSNumber, number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    func title(_ row: [String: Any]) -> String {
        if let job = row["managed_job"] as? String { return job }
        let path = row["path"] as? String ?? "未知进程"
        return path.hasPrefix("/") ? URL(fileURLWithPath: path).lastPathComponent : path
    }
    let titles = ["cpu_critical": "整机 CPU 持续接近满载", "cpu_sustained": "整机 CPU 长时间偏高",
                  "windowserver_sustained": "WindowServer 持续占用多个核心", "process_sustained": "进程持续占用一个或更多核心",
                  "memory_warning": "内存警告伴随 CPU 或换页负载", "memory_critical": "内存压力持续严重",
                  "thermal_serious": "系统持续报告较高热压力", "thermal_critical": "系统持续报告严重热压力"]
    var facts: [String] = []
    var hypotheses: [String] = []
    var recommendations: [String] = []
    if let cpu = numeric("cpu_percent") {
        let cores = max(1, Int(numeric("logical_cores") ?? 1))
        facts.append(String(format: "整机 CPU %.1f%%，共 %d 个逻辑核心；进程 100%% 表示一个核心，不是整机满载。", cpu, cores))
    }
    if snapshot["prompt_cpu_qualified"] as? Bool == true, let pulse = numeric("prompt_cpu_percent") {
        let threshold = numeric("prompt_cpu_threshold") ?? 95
        let duration = numeric("prompt_sustained_seconds") ?? 5
        facts.append(String(format: "自动提示依据独立逐秒采样：整机 CPU 已连续 %.0f 秒严格大于 %.1f%%，最近逐秒读数 %.1f%%。上面的完整诊断 CPU 使用较长采样窗口，平均值可能较低；两者时间范围不同。", duration, threshold, pulse))
    }
    let pressure = Int(numeric("memory_pressure") ?? 0)
    facts.append("内存压力：" + ([1: "正常", 2: "警告", 4: "严重"][pressure] ?? "采样不可用") + "。")
    if let used = numeric("swap_used_mb") {
        facts.append(String(format: "已用交换空间 %.0f MB 是存量，不能单凭这个数值判断当前正在频繁换页。", used))
    }
    if let input = numeric("swap_in_mbps"), let output = numeric("swap_out_mbps") {
        facts.append(String(format: "本采样窗口交换读入 %.2f MB/s、写出 %.2f MB/s；速率用于判断当前换页活动。", input, output))
    } else { facts.append("当前没有可比较的换页速率，首次采样或采样断档时保持未知。") }
    if let thermal = numeric("thermal_state") {
        facts.append("系统热压力：" + ([0: "正常", 1: "轻度", 2: "较高", 3: "严重"][Int(thermal)] ?? "未知") + "。")
    }
    let top = snapshot["top"] as? [[String: Any]] ?? []
    let topMemory = snapshot["top_memory"] as? [[String: Any]] ?? []
    let processRows = snapshot["top_processes"] as? [[String: Any]] ?? []
    if let row = top.first, let cpu = row["cpu_core_percent"] as? NSNumber {
        facts.append(String(format: "CPU 清单首项 %@：%.1f%% 单核口径；它是当前采样记录，不能据此断定程序卡死。", title(row), cpu.doubleValue))
    }
    if reasons.contains("windowserver_sustained") {
        hypotheses.append("WindowServer 的负载与窗口合成和显示有关；现有样本未定位具体应用、窗口或显示器，不能把它全部归到 Ghostty。")
        recommendations.append("保留终端任务，检查持续动画、屏幕共享、录屏和高刷新内容；每次只改变一项并复测 WindowServer，关闭应用前先确认其中的任务。")
    }
    if reasons.contains(where: { $0.hasPrefix("memory_") }) {
        hypotheses.append("内存压力可能来自多个应用叠加；需要结合本轮换页速率和内存清单，不能把交换空间存量当成持续换页的证据。")
        if !topMemory.isEmpty {
            let names = topMemory.prefix(3).map { row -> String in
                let rss = (row["rss_mb_sum"] as? NSNumber)?.intValue ?? 0
                return "\(title(row))（RSS 合计约 \(rss) MB）"
            }
            facts.append("内存清单前项：" + names.joined(separator: "、") + "。RSS 可能重复计入共享页。")
            recommendations.append("优先检查内存清单中的 " + names.joined(separator: "、") + "；保存工作后再选择可关闭的应用。")
        } else { recommendations.append("当前缺少按内存排序的清单，先补采内存占用；不要用 CPU 排名代替内存排名。") }
    }
    if reasons.contains(where: { $0.hasPrefix("cpu_") || $0 == "process_sustained" }) {
        hypotheses.append("持续高 CPU 可能是有效计算、索引、渲染或重试；高占用本身不等于卡死，需要结合任务进展和相邻样本。")
        recommendations.append("检查高 CPU 项是否仍在完成预期任务；有明确冗余的受管后台任务可降低频率或并发，用户应用和终端任务由本人选择是否退出。")
    }
    if reasons.contains(where: { $0.hasPrefix("thermal_") }) {
        recommendations.append("系统正在报告热压力；检查散热条件，减少可延后的并发负载，再比较热压力与 CPU 是否回落。")
    }
    if processRows.contains(where: { ($0["terminal_protected"] as? Bool) == true }) || top.contains(where: { ($0["terminal_protected"] as? Bool) == true }) {
        recommendations.append("清单包含受保护的终端任务，资源监控不会自动结束这些任务。")
    }
    if recommendations.isEmpty { recommendations.append("继续观察相邻采样和正在执行的任务；没有足够证据时不自动结束进程。") }
    return ["reason_titles": reasons.map { titles[$0] ?? $0 }, "facts": facts, "hypotheses": hypotheses,
            "recommendations": recommendations,
            "learning_summary": "整机 CPU 与单核 CPU 分母不同；高 CPU 不等于卡死。内存压力表示当前供需状态，交换空间占用是存量，换入换出速率才反映当前活动。WindowServer 是绘制承载进程，具体负载来源须另做对照。提示表示需要检查，资源监控不会自动关闭用户进程。"]
}
