import Cocoa

final class ResourceTopDownStack: NSStackView {
    override var isFlipped: Bool { true }
}

final class ResourcePrompt: NSObject, NSWindowDelegate {
    let panel: NSPanel
    let rootURL: URL
    let promptID: String
    let preview: Bool
    let event: [String: Any]
    let candidates: [[String: Any]]
    let log: ([String: Any]) -> Void
    var choices: [(NSButton, [String: Any])] = []
    var finished = false
    var busy = false
    var confirm: NSButton!
    var resultLabel: NSTextField!
    var replacement: ResourcePrompt?
    var evidenceScroll: NSScrollView!
    var recommendButton: NSButton!
    var memoryFirst: Bool { (event["reasons"] as? [String] ?? []).contains { $0.hasPrefix("memory") } }
    init(root: URL, promptID: String, event: [String: Any], preview: Bool, timeout: Double, log: @escaping ([String: Any]) -> Void) {
        self.rootURL = root; self.promptID = promptID; self.preview = preview; self.event = event; self.log = log
        let snapshot = event["latest"] as? [String: Any] ?? event
        let reasons = event["reasons"] as? [String] ?? []
        let historical = ["recovered", "interrupted"].contains(event["status"] as? String ?? "")
        self.candidates = resourceCandidates(snapshot: snapshot, memoryFirst: reasons.contains(where: { $0.hasPrefix("memory") })).map { candidate in
            guard historical else { return candidate }
            var row = candidate; row["kind"] = "protected"; row["recommendation"] = "历史事件仅供复盘"
            row["impact"] = "请从菜单栏查看新的实时建议；不使用已恢复事件结束当前进程。"; return row
        }
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: min(760, frame.width - 60), height: min(760, frame.height - 60)), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = preview ? "资源监控 · 预览（不执行退出）" : "资源监控 · 原因与处理建议"
        panel.delegate = self; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        let container = NSView(); panel.contentView = container
        let stack = ResourceTopDownStack(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        evidenceScroll = scroll
        scroll.documentView = stack
        let footer = NSStackView(); footer.orientation = .horizontal; footer.spacing = 8
        let later = NSButton(title: "暂不关闭", target: self, action: #selector(dismiss))
        later.keyEquivalent = "\u{1b}"
        confirm = NSButton(title: preview ? "预览确认" : "关闭已选", target: self, action: #selector(applyChoices))
        confirm.isEnabled = false
        let details = NSButton(title: "查看完整记录", target: self, action: #selector(openReport))
        let refresh = NSButton(title: "刷新状态", target: self, action: #selector(refreshAdvice))
        refresh.isEnabled = !preview
        recommendButton = NSButton(title: "一键勾选推荐项", target: self, action: #selector(selectRecommended))
        recommendButton.isEnabled = !recommendedResourceCandidates(candidates, memoryFirst: memoryFirst).isEmpty
        recommendButton.toolTip = "仅勾选符合条件的高占用普通应用，最多三项。终端、系统和文稿/代码编辑器排除。"
        footer.addArrangedSubview(recommendButton); footer.addArrangedSubview(confirm); footer.addArrangedSubview(later); footer.addArrangedSubview(refresh); footer.addArrangedSubview(details)
        for v in [scroll, footer] { v.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(v) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: container.topAnchor), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18), footer.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -18),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        func label(_ text: String, bold: Bool = false) {
            let field = NSTextField(wrappingLabelWithString: text); field.font = bold ? .boldSystemFont(ofSize: 15) : .systemFont(ofSize: 13)
            field.isSelectable = true; field.setContentCompressionResistancePriority(.required, for: .vertical)
            stack.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true
        }
        let analysis = event["analysis"] as? [String: Any] ?? incidentAnalysis(snapshot: snapshot, reasons: reasons)
        let titles = analysis["reason_titles"] as? [String] ?? []
        label(titles.isEmpty ? "资源状态与建议" : titles.joined(separator: " · "), bold: true)
        let sampled = ISO8601DateFormatter().date(from: snapshot["time"] as? String ?? "")
        let local = DateFormatter(); local.locale = Locale(identifier: "zh_CN"); local.timeZone = TimeZone(identifier: "Asia/Shanghai"); local.dateFormat = "M月d日 HH:mm:ss"
        let status = ["active": "持续异常", "recovered": "已恢复", "interrupted": "监控曾中断", "monitoring": "当前观察", "preview": "预览演示"][event["status"] as? String ?? ""] ?? "当前观察"
        label("采样时间：\(sampled.map(local.string) ?? "未知")；\(status)。过期记录只用于分析，不能关闭新进程。")
        label("先保留工作，再选择处理。高占用不等于死进程；系统服务、网络连接和终端任务受到保护。\(Int(timeout)) 秒后提示自动收起，记录仍保留在菜单栏“负载”中。")
        for (key, title) in [("facts", "观察到什么"), ("hypotheses", "可能原因（尚未证明）"), ("recommendations", "怎么处理与验证")] {
            label(title, bold: true)
            for line in analysis[key] as? [String] ?? [] { label("• " + line) }
        }
        if let diagnostics = event["diagnostics"] as? [String: Any] {
            label("本次堆栈诊断", bold: true)
            for result in diagnostics["samples"] as? [[String: Any]] ?? [] {
                if let summary = result["summary"] as? [String: Any], let observation = summary["observation"] as? String { label(observation) }
            }
            label("堆栈是当时执行位置的线索；未定位到具体来源时仍保留不确定性。完整证据可从事件记录查看。")
        }
        label("可选操作（默认不选）", bold: true)
        label("可用“一键勾选推荐项”选择高占用应用，检查清单后点“关闭已选”即执行正常退出。文稿和代码编辑器不自动勾选；应用自身的保存提示会保留。")
        for candidate in candidates {
            let kind = candidate["kind"] as? String ?? "protected"
            let cpu = candidate["cpu_core_percent"] as? Double ?? 0
            let title = String(format: "%@  ·  %.0f%% 单核  ·  %@ MB", candidate["name"] as? String ?? "", cpu, String(describing: candidate["rss_mb_sum"] ?? 0))
            let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(selectionChanged))
            button.isEnabled = kind != "protected"
            stack.addArrangedSubview(button); choices.append((button, candidate))
            label((candidate["recommendation"] as? String ?? "") + "。" + (candidate["impact"] as? String ?? ""))
        }
        label("讲清楚原理", bold: true)
        label(analysis["learning_summary"] as? String ?? "先比较同一时间窗口的负载，再针对一个变量处理，最后观察负载是否恢复。")
        resultLabel = NSTextField(wrappingLabelWithString: "")
        resultLabel.font = .boldSystemFont(ofSize: 13); resultLabel.isSelectable = true
        stack.addArrangedSubview(resultLabel)
        resultLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true
        panel.center()
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self, !self.finished, !self.busy else { return }
            self.finish("timed_out")
        }
    }
    func show() {
        panel.orderFrontRegardless() // Deliberately do not activate the app or make the panel key.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.panel.isVisible else { self?.finish("presentation_failed"); return }
            self.panel.contentView?.layoutSubtreeIfNeeded()
            if let document = self.evidenceScroll.documentView {
                let y = document.isFlipped ? 0 : max(0, document.bounds.height - self.evidenceScroll.contentView.bounds.height)
                self.evidenceScroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                self.evidenceScroll.reflectScrolledClipView(self.evidenceScroll.contentView)
            }
            self.emit("prompt_presented")
        }
    }
    func emit(_ name: String, extra: [String: Any] = [:]) {
        var record: [String: Any] = ["event": name, "prompt_id": promptID, "incident_id": event["id"] ?? "", "preview": preview, "time": ISO8601DateFormatter().string(from: Date())]
        record.merge(extra) { _, new in new }; log(record)
        if !preview {
            do { try IncidentStore.save(record, to: rootURL.appendingPathComponent("prompt-state.json")) }
            catch { FileHandle.standardError.write(Data("prompt-state write failed: \(error)\n".utf8)) }
        }
    }
    @objc func selectionChanged() { confirm.isEnabled = choices.contains { $0.0.state == .on && $0.0.isEnabled } }
    @objc func selectRecommended() {
        guard !busy else { return }
        let recommended = recommendedResourceCandidates(candidates, memoryFirst: memoryFirst)
        let ids = Set(recommended.compactMap { $0["pid"] as? Int })
        for (button, row) in choices { button.state = button.isEnabled && ids.contains(row["pid"] as? Int ?? 0) ? .on : .off }
        selectionChanged()
        resultLabel.stringValue = recommended.isEmpty ? "当前没有可自动勾选的推荐项，或采样已过期。请刷新状态，不会勉强选择。" : "已勾选 \(recommended.count) 项：\n" + recommended.map { "\($0["name"] ?? "")：\($0["recommendation_reason"] ?? "占用较高，确认不用后可关闭")" }.joined(separator: "\n")
        resultLabel.scrollToVisible(resultLabel.bounds)
        emit("recommendations_selected", extra: ["selected_count": recommended.count, "pids": Array(ids)])
    }
    @objc func dismiss() { if !busy { finish("cancelled") } }
    @objc func refreshAdvice() {
        guard !busy, !preview else { return }
        guard let data = try? Data(contentsOf: rootURL.appendingPathComponent("latest-advice.json")),
              let fresh = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            resultLabel.stringValue = "暂时无法读取新建议，请稍后从菜单栏重试。"; return
        }
        emit("prompt_refreshed")
        finished = true; panel.orderOut(nil)
        let next = ResourcePrompt(root: rootURL, promptID: promptID, event: fresh, preview: false, timeout: 120, log: log)
        replacement = next; next.show()
    }
    @objc func openReport() {
        let id = event["id"] as? String ?? ""
        let path = rootURL.appendingPathComponent("incidents/\(id).md")
        NSWorkspace.shared.open(FileManager.default.fileExists(atPath: path.path) ? path : rootURL.appendingPathComponent("latest-advice.md"))
    }
    @objc func applyChoices() {
        let selected = choices.filter { $0.0.state == .on && $0.0.isEnabled }.map { $0.1 }
        guard !selected.isEmpty, !busy else { return }
        if preview { emit("preview_confirmed", extra: ["selected_count": selected.count]); finish("preview_closed"); return }
        busy = true
            self.confirm.isEnabled = false
            self.recommendButton.isEnabled = false
            self.emit("actions_confirmed", extra: ["selected_count": selected.count])
            DispatchQueue.global(qos: .utility).async {
                var results: [String] = []
                for candidate in selected {
                    let result = performResourceAction(candidate)
                    let outcome = result["outcome"] as? String ?? "unknown"
                    let detail: String
                    switch outcome {
                    case "original_process_exited": detail = "原进程已退出；监控会继续记录负载是否恢复。"
                    case "still_running_or_awaiting_save": detail = "仍在运行，可能等待保存或拒绝退出；没有强制关闭。"
                    default: detail = "未执行：身份、时效或保护检查未通过，请刷新建议。"
                    }
                    results.append("\(candidate["name"] ?? "目标")：\(detail)")
                    DispatchQueue.main.sync { self.emit("action_result", extra: result) }
                }
                let summary = results.joined(separator: "\n")
                DispatchQueue.main.async {
                    self.busy = false; self.emit("actions_completed"); self.resultLabel.stringValue = summary
                    for (button, _) in self.choices { button.isEnabled = false }
                    self.resultLabel.scrollToVisible(self.resultLabel.bounds)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { if !self.finished { self.finish("result_timed_out") } }
                }
            }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { if busy { return false }; finish("cancelled"); return true }
    func finish(_ reason: String) {
        guard !finished else { return }; finished = true; emit(reason); panel.orderOut(nil)
        NSApplication.shared.terminate(nil)
    }
}

final class ResourceMenu: NSObject {
    let item: NSStatusItem
    let showAdvice: () -> Void
    let openEvidence: () -> Void
    var status: NSMenuItem
    init(showAdvice: @escaping () -> Void, openEvidence: @escaping () -> Void) {
        self.showAdvice = showAdvice; self.openEvidence = openEvidence
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status = NSMenuItem(title: "正在采样…", action: nil, keyEquivalent: "")
        super.init()
        item.button?.title = "负载"
        let menu = NSMenu(); menu.addItem(status); menu.addItem(.separator())
        let advice = NSMenuItem(title: "查看原因与推荐操作", action: #selector(show), keyEquivalent: ""); advice.target = self; menu.addItem(advice)
        let evidence = NSMenuItem(title: "查看历史事件", action: #selector(open), keyEquivalent: ""); evidence.target = self; menu.addItem(evidence)
        item.menu = menu
    }
    @objc func show() { showAdvice() }
    @objc func open() { openEvidence() }
    func update(cpu: Double, severity: String, incident: Bool) {
        status.title = String(format: "整机 CPU %.0f%% · %@", cpu, severity == "normal" ? "监控中" : "有持续负载")
        item.button?.title = incident ? "负载 !" : "负载"
        item.button?.toolTip = "点击查看原因分析、推荐操作和历史记录。"
    }
}
