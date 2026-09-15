import Foundation

// Local evidence only. Never write application arguments, document names or network data.
final class IncidentStore {
    let directory: URL
    private(set) var currentID: String?
    private var record: [String: Any] = [:]
    private var recent: [[String: Any]] = []
    private var lastWrite = 0.0
    init(directory: URL, recoverInterrupted: Bool = true) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // An interrupted incident is preserved, not silently reported as recovered.
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where recoverInterrupted && url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url), var old = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], old["status"] as? String == "active" else { continue }
            old["status"] = "interrupted"; old["end_note"] = "监控重启，未证明负载已恢复"
            try Self.save(old, to: url)
            try markdown(old).write(to: url.deletingPathExtension().appendingPathExtension("md"), atomically: true, encoding: .utf8)
        }
    }
    static func save(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func observe(snapshot: [String: Any], decision: IncidentDecision, now: Double) throws -> [String: Any]? {
        recent.append(snapshot)
        if recent.count > 24 { recent.removeFirst(recent.count - 24) }
        if currentID == nil && decision.shouldRecord {
            let id = UUID().uuidString.lowercased(); currentID = id
            record = ["id": id, "status": "active", "started_at": snapshot["time"] ?? "", "started_epoch": now,
                      "prelude": recent, "peak_cpu_percent": 0.0, "first_snapshot": snapshot, "timeline": [], "updates": 0, "reasons": decision.reasons]
        }
        guard let id = currentID else { return nil }
        if record["peak_snapshot"] == nil || (snapshot["cpu_percent"] as? Double ?? 0) > (record["peak_cpu_percent"] as? Double ?? 0) {
            record["peak_snapshot"] = snapshot
            record["peak_cpu_percent"] = snapshot["cpu_percent"] as? Double ?? 0
        }
        let reasons = Array(Set((record["reasons"] as? [String] ?? []) + decision.reasons)).sorted()
        record["reasons"] = reasons
        record["latest"] = snapshot; record["updated_at"] = snapshot["time"]
        record["severity"] = decision.severity
        if !decision.recovered { record["last_hot_snapshot"] = snapshot }
        let evidence = decision.recovered ? (record["peak_snapshot"] as? [String: Any] ?? snapshot) : snapshot
        record["analysis"] = incidentAnalysis(snapshot: evidence, reasons: reasons)
        record["analysis_sample_time"] = evidence["time"]
        if let data = try? Data(contentsOf: directory.appendingPathComponent(id + "-diagnostics.json")), let diagnostics = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { record["diagnostics"] = diagnostics }
        if decision.recovered { record["status"] = "recovered"; record["recovery_snapshot"] = snapshot; record["ended_at"] = snapshot["time"]; record["end_note"] = "持续过载触发组合已消失；可能仍有内存 warning。时间相关不等于已证明某项操作修复了根因。" }
        if now - lastWrite >= 60 || decision.shouldRecord || decision.shouldPrompt || decision.recovered {
            record["updates"] = (record["updates"] as? Int ?? 0) + 1
            var timeline = record["timeline"] as? [[String: Any]] ?? []
            timeline.append(snapshot)
            if timeline.count > 120 { timeline.removeFirst(timeline.count - 120) }
            record["timeline"] = timeline
            try Self.save(record, to: directory.appendingPathComponent(id + ".json"))
            try markdown(record).write(to: directory.appendingPathComponent(id + ".md"), atomically: true, encoding: .utf8)
            lastWrite = now
        }
        let result = record
        if decision.recovered { currentID = nil; record = [:] }
        return result
    }
    private func markdown(_ r: [String: Any]) -> String {
        let analysis = r["analysis"] as? [String: Any] ?? [:]
        func lines(_ value: Any?) -> String {
            guard let value = value else { return "待采集" }
            if let s = value as? String { return s }
            if let list = value as? [String] { return list.map { "- " + $0 }.joined(separator: "\n") }
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: value)
        }
        return """
        # Mac 负载事件 \(r["id"] ?? "")

        状态：\(r["status"] ?? "")；开始：\(r["started_at"] ?? "")；最后记录：\(r["updated_at"] ?? "")。
        峰值整机 CPU：\(r["peak_cpu_percent"] ?? "")%。时间字段为 UTC（上海时间加 8 小时）。

        ## 观察事实
        以下分析基于 \(r["analysis_sample_time"] ?? "") 的采样；恢复时保留峰值证据，当前状态见上方及 JSON 的 recovery_snapshot。
        \(lines(analysis["facts"]))

        ## 可能原因与限制
        \(lines(analysis["hypotheses"]))

        ## 推荐处理
        \(lines(analysis["recommendations"]))

        ## 理解与复述
        \(lines(analysis["learning_summary"]))

        ## 深层诊断
        \(lines((r["diagnostics"] as? [String: Any])?["status"]))。同目录 \(r["id"] ?? "")-diagnostics.json 记录最多两个进程的堆栈、权限或身份不匹配说明。无管理员权限时系统进程可能无法采样；不会据此编造根因。

        \(r["end_note"] ?? "事件持续中。高占用不等于死进程；未自动结束用户应用。")
        同名 JSON 保存进程身份、告警前采样及最新证据；处理结果在上级 actions.jsonl。系统服务和终端任务受保护，文件与应用不会因高负载被删除。
        """
    }
}
