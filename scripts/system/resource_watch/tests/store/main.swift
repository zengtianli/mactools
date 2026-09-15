import Foundation

var passed = 0
func check(_ yes: @autoclosure () -> Bool, _ name: String) { guard yes() else { fatalError(name) }; passed += 1 }
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("resource-store-test-" + UUID().uuidString)
defer { try? FileManager.default.removeItem(at: dir) }
let store = try IncidentStore(directory: dir)
func snapshot(_ second: Double, _ cpu: Double) -> [String: Any] {
    ["time": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: second)), "cpu_percent": cpu,
     "memory_pressure": 2, "logical_cores": 10, "swap_in_mbps": 0.0, "swap_out_mbps": 0.0, "top": []]
}
let normal = IncidentDecision(reasons: [], severity: "normal", shouldRecord: false, shouldPrompt: false, recovered: false)
let hot = IncidentDecision(reasons: ["cpu_critical"], severity: "critical", shouldRecord: true, shouldPrompt: true, recovered: false)
let recover = IncidentDecision(reasons: [], severity: "normal", shouldRecord: true, shouldPrompt: false, recovered: true)
_ = try store.observe(snapshot: snapshot(0, 30), decision: normal, now: 0)
check(store.currentID == nil, "healthy does not manufacture incident")
let first = try store.observe(snapshot: snapshot(60, 94), decision: hot, now: 60)!
let id = first["id"] as! String
check((first["prelude"] as? [[String: Any]])?.count == 2, "prelude preserves context")
_ = try store.observe(snapshot: snapshot(120, 99), decision: hot, now: 120)
let ended = try store.observe(snapshot: snapshot(180, 25), decision: recover, now: 180)!
check(store.currentID == nil, "recovery closes current")
check(ended["status"] as? String == "recovered", "recovered status")
check((ended["peak_snapshot"] as? [String: Any])?["cpu_percent"] as? Double == 99, "peak evidence remains")
check((ended["recovery_snapshot"] as? [String: Any])?["cpu_percent"] as? Double == 25, "recovery separate from peak")
check((ended["timeline"] as? [[String: Any]])?.count == 3, "bounded timeline added")
let disk = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent(id + ".json"))) as! [String: Any]
check(disk["status"] as? String == "recovered", "disk roundtrip")
let text = try String(contentsOf: dir.appendingPathComponent(id + ".md"), encoding: .utf8)
check(text.contains("recovered") && text.contains("99"), "human report preserves outcome and peak")
let next = try store.observe(snapshot: snapshot(240, 96), decision: hot, now: 240)!
let nextID = next["id"] as! String
_ = try IncidentStore(directory: dir, recoverInterrupted: false)
let still = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent(nextID + ".json"))) as! [String: Any]
check(still["status"] as? String == "active", "read-only/once cannot mark active interrupted")
_ = try IncidentStore(directory: dir)
let interrupted = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent(nextID + ".json"))) as! [String: Any]
check(interrupted["status"] as? String == "interrupted", "restart marks unknown recovery")
let interruptedText = try String(contentsOf: dir.appendingPathComponent(nextID + ".md"), encoding: .utf8)
check(interruptedText.contains("interrupted") && interruptedText.contains("未证明"), "markdown agrees after restart")
let permission = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(nextID + ".json").path)[.posixPermissions] as! NSNumber
check(permission.intValue == 0o600, "evidence permissions")
print("\(passed) store checks passed")
