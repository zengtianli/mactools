import AppKit
import SwiftUI
import Foundation

struct Step: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let done: Bool
    let status: String
}
struct Job: Decodable, Identifiable {
    let id: String
    let name: String
    let group: String
    let schedule: String
    let status: String
    let phase: String
    let detail: String
    let error: String?
    let steps: [Step]
    let done: Int
    let total: Int
    let mode: String?
    let defaultMode: String
    let elapsed: Int?
    let startedAt: Double?
    let evidence: String
    let period: String?
    let receipt: String?
    let url: String?
    let updatedAt: Double?
    var needsAttention: Bool { ["failed", "interrupted", "unknown", "unloaded"].contains(status) }
    var color: Color { needsAttention ? .orange : status == "running" ? .blue : status == "success" ? .green : .secondary }
    var label: String {
        switch status {
        case "running": return "运行中"
        case "service": return "常驻服务"
        case "success": return "已完成"
        case "failed", "interrupted": return "需处理"
        case "unknown": return "状态未知"
        case "paused": return "已暂停"
        case "unloaded": return "未加载"
        default: return "等待中"
        }
    }
}
struct Event: Decodable, Identifiable {
    let id: String
    let name: String
    let type: String
    let at: Double
    let phase: String
    let notification: String
    let alreadyRunning: Bool?
    var label: String {
        if alreadyRunning == true { return "正在运行" }
        return ["running": "开始运行", "progress": "进度更新", "success": "已完成", "ended": "本轮结束", "failed": "需要处理"][type] ?? type
    }
}
struct Snapshot: Decodable {
    let tasks: [Job]
    let events: [Event]
    let updatedAt: Double?
    let error: String?
    let modes: [String: String]
}
func decoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}

@MainActor final class Model: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var connectionError: String?
    @Published var settingError: String?
    @Published var filter = "运行与异常"
    @Published var search = ""
    @Published var expanded = Set<String>()
    var onChange: (() -> Void)?
    var timer: Timer?
    var busy = false
    var backend: Process?
    var receiptWindow: NSWindowController?
    var lastBackendStart = Date.distantPast
    let base = "http://127.0.0.1:8798"
    let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 3
        c.urlCache = nil
        return URLSession(configuration: c)
    }()
    var running: [Job] { snapshot?.tasks.filter { $0.status == "running" } ?? [] }
    var failed: [Job] { snapshot?.tasks.filter { $0.needsAttention } ?? [] }
    var visible: [Job] {
        let jobs = snapshot?.tasks ?? []
        return jobs.filter { job in
            let selected = filter == "全部" || filter == "最近完成" && job.status == "success" || filter == "运行与异常" && (job.status == "running" || job.needsAttention)
            return selected && (search.isEmpty || job.name.localizedCaseInsensitiveContains(search) || job.id.localizedCaseInsensitiveContains(search))
        }.sorted {
            let rank = ["running": 0, "failed": 1, "interrupted": 1, "unknown": 1, "success": 2, "waiting": 3, "paused": 4]
            return (rank[$0.status, default: 5], $0.name) < (rank[$1.status, default: 5], $1.name)
        }
    }
    func start() {
        startBackend()
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetch() }
        }
    }
    func startBackend() {
        guard backend?.isRunning != true, Date().timeIntervalSince(lastBackendStart) > 10 else { return }
        lastBackendStart = Date()
        let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let script = root.appendingPathComponent("scripts/system/automation_monitor.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/python3")
        process.arguments = [script.path]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["AUTOMATION_MONITOR_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        process.environment = env
        // Python collector is a child of this menu app; it never launches business jobs.
        do {
            try process.run()
            backend = process
        } catch { connectionError = "进度服务无法启动：\(error.localizedDescription)" }
    }
    func fetch() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let (data, response) = try await session.data(from: URL(string: base + "/api/state")!)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let value = try decoder().decode(Snapshot.self, from: data)
                snapshot = value
                connectionError = value.error
                if let stamp = value.updatedAt, Date().timeIntervalSince1970 - stamp > 30 {
                    connectionError = "进度超过 30 秒未刷新，下面保留最后一次状态"
                }
                onChange?()
            } catch {
                connectionError = "进度服务暂未连接；保留最后一次状态，稍后自动重连"
                startBackend()
                onChange?()
            }
        }
    }
    func setMode(_ job: Job, _ mode: String) {
        Task {
            do {
                var req = URLRequest(url: URL(string: base + "/api/settings")!)
                req.httpMethod = "POST"
                req.setValue(base, forHTTPHeaderField: "Origin")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: ["task": job.id, "mode": mode])
                let (_, response) = try await session.data(for: req)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                settingError = nil
                fetch()
            } catch { settingError = "提醒设置未保存，请重试" }
        }
    }
    func showReceipt(_ job: Job) {
        let controller = NSHostingController(rootView: ReceiptView(initialJob: job, model: self))
        let window = NSWindow(contentViewController: controller)
        window.title = job.name + " · 运行回执"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 700, height: 560))
        window.minSize = NSSize(width: 500, height: 360)
        window.center()
        receiptWindow = NSWindowController(window: window)
        receiptWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct ReceiptView: View {
    let initialJob: Job
    @ObservedObject var model: Model
    var job: Job { model.snapshot?.tasks.first { $0.id == initialJob.id } ?? initialJob }
    @State private var tab = "概览"
    var raw: String {
        guard let path = job.receipt else { return "暂无运行回执" }
        let url = URL(fileURLWithPath: path)
        let source = tab == "运行日志" ? url.deletingPathExtension().appendingPathExtension("log") : url
        guard let data = try? Data(contentsOf: source) else { return "本次任务没有可读取的\(tab)文件。" }
        if tab == "原始回执", let value = try? JSONSerialization.jsonObject(with: data),
           let formatted = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            return String(decoding: formatted, as: UTF8.self)
        }
        // Keep large generation logs responsive; the original remains available in Finder.
        let tail = data.suffix(200_000)
        let lines = String(decoding: tail, as: UTF8.self).components(separatedBy: .newlines)
        return (data.count > tail.count || lines.count > 200 ? "显示最近 200 行；完整日志可用下方按钮查看。\n\n" : "") + lines.suffix(200).joined(separator: "\n")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(job.name).font(.title2.bold())
                Spacer()
                Text(job.label).foregroundStyle(job.color)
            }
            Picker("回执内容", selection: $tab) {
                Text("概览").tag("概览")
                Text("运行日志").tag("运行日志")
                Text("原始回执").tag("原始回执")
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if tab == "概览" {
                        if let period = job.period { Text("交易日：\(period)").font(.headline) }
                        Text(job.phase).font(.headline)
                        Text(job.detail)
                        if let error = job.error { Text(error).foregroundStyle(.orange) }
                        ForEach(job.steps) { step in
                            Label(step.name, systemImage: step.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(step.done ? .green : .secondary)
                        }
                        Divider()
                        Label(job.schedule, systemImage: "clock")
                        Text("依据：\(job.evidence)").foregroundStyle(.secondary)
                    } else {
                        Text(raw).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
            HStack {
                if let raw = job.url, let url = URL(string: raw) {
                    Button("阅读结果") { NSWorkspace.shared.open(url) }
                }
                Spacer()
                if let path = job.receipt {
                    Button("在 Finder 中查看原文件") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                }
            }
        }.padding(20).frame(minWidth: 460, minHeight: 320)
    }
}

struct JobView: View {
    let job: Job
    @ObservedObject var model: Model
    var expanded: Bool { model.expanded.contains(job.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if expanded { model.expanded.remove(job.id) } else { model.expanded.insert(job.id) }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(job.color).frame(width: 7, height: 7)
                    Text(job.name).fontWeight(.semibold)
                    Spacer()
                    Text(job.label).font(.caption).foregroundStyle(job.color)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(job.name)，\(job.label)，展开详情")
            if !job.phase.isEmpty { Text(job.phase).font(.callout).foregroundStyle(.secondary) }
            if job.total > 0 {
                HStack {
                    ProgressView(value: Double(job.done), total: Double(job.total)).tint(job.color)
                    Text("\(job.done)/\(job.total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if job.done == job.total && job.status == "running" {
                    Text("内容检查完成，仍在发布与核验").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let elapsed = job.elapsed, job.status == "running" {
                Text("\(job.startedAt == nil ? "本次观察已运行" : "已运行") \(elapsed / 60) 分 \(elapsed % 60) 秒").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if expanded {
                if let period = job.period { Text("复盘交易日：\(period)").font(.caption).foregroundStyle(.secondary) }
                ForEach(job.steps) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : step.status == "failed" ? "exclamationmark.circle" : step.status == "running" ? "arrow.triangle.2.circlepath" : "circle")
                            .foregroundStyle(step.done ? .green : step.status == "failed" ? .orange : .secondary)
                        Text(step.name).font(.callout)
                    }
                }
                Text(job.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let error = job.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                Divider()
                Label(job.schedule, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                Text("依据：\(job.evidence)").font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Text("提醒").font(.caption)
                    Picker("提醒", selection: Binding(get: { job.mode ?? job.defaultMode }, set: { model.setMode(job, $0) })) {
                        Text("启动、进度、结束").tag("all")
                        Text("仅结束与异常").tag("result")
                        Text("仅异常").tag("errors")
                        Text("只在菜单栏显示").tag("silent")
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
                HStack {
                    if let raw = job.url, let url = URL(string: raw), ["http", "https"].contains(url.scheme ?? "") {
                        Button("阅读结果") { NSWorkspace.shared.open(url) }
                    }
                    if job.receipt != nil {
                        Button("查看运行回执") { model.showReceipt(job) }
                    }
                    Spacer()
                }.controlSize(.small)
            }
        }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct Panel: View {
    @ObservedObject var model: Model
    let height: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("自动化").font(.title2.bold())
                    Text("\(model.running.count) 项运行中 · \(model.failed.count) 项需处理").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.fetch() } label: { Image(systemName: "arrow.clockwise") }.help("刷新状态").keyboardShortcut("r", modifiers: .command)
            }
            if let message = model.connectionError ?? model.settingError {
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            TextField("搜索任务", text: $model.search).textFieldStyle(.roundedBorder)
            Picker("显示", selection: $model.filter) {
                Text("运行与异常").tag("运行与异常")
                Text("最近完成").tag("最近完成")
                Text("全部").tag("全部")
            }.pickerStyle(.segmented)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    if model.visible.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.green)
                            Text(model.snapshot == nil ? "正在读取自动化状态…" : "当前没有匹配的任务")
                            Text("等待中的定时任务可在“全部”查看").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                    ForEach(model.visible) { JobView(job: $0, model: model) }
                    if let events = model.snapshot?.events, !events.isEmpty {
                        Text("最近动态").font(.headline).padding(.top, 10)
                        ForEach(Array(events.prefix(8))) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(event.name + " · " + event.label).font(.caption).fontWeight(.medium)
                                    Spacer()
                                    Text(Date(timeIntervalSince1970: event.at), style: .time).font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(event.phase).font(.caption).foregroundStyle(.secondary)
                                if event.notification == "failed" { Text("系统通知发送失败，进度仍保留在这里").font(.caption2).foregroundStyle(.orange) }
                            }.padding(.vertical, 4)
                        }
                    }
                }.padding(.trailing, 2)
            }
            HStack {
                if let stamp = model.snapshot?.updatedAt {
                    Text("更新于 \(Date(timeIntervalSince1970: stamp).formatted(date: .omitted, time: .standard))")
                } else { Text("正在连接") }
                Spacer()
                Text("每 5 秒刷新 · 本机")
            }.font(.caption2).foregroundStyle(.secondary)
        }.padding(16).frame(width: 430, height: height)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    var item: NSStatusItem!
    let popover = NSPopover()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "自动化"
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "自动化进度")
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        model.onChange = { [weak self] in self?.updateTitle() }
        model.start()
    }
    func updateTitle() {
        let active = model.running
        let investment = active.first { $0.id == "com.tianli.optionsdesk-daily" }
        if model.connectionError != nil { item.button?.title = "自动化 !" }
        else if let job = investment, job.total > 0 {
            item.button?.title = job.done == job.total ? (job.phase == "生成与自审" ? "复盘·自审" : "复盘·发布") : "复盘 \(job.done)/\(job.total)"
        }
        else if !active.isEmpty { item.button?.title = "自动化 \(active.count)" }
        else { item.button?.title = model.failed.isEmpty ? "自动化" : "自动化 !\(model.failed.count)" }
        item.button?.toolTip = "\(active.count) 项运行中，\(model.failed.count) 项需要处理。点击查看进度与结果。"
        item.button?.setAccessibilityLabel(item.button?.toolTip)
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            model.fetch()
            let height = min(CGFloat(640), (button.window?.screen?.visibleFrame.height ?? 720) - 40)
            let controller = NSHostingController(rootView: Panel(model: model, height: height))
            controller.preferredContentSize = NSSize(width: 430, height: height)
            popover.contentViewController = controller
            popover.contentSize = NSSize(width: 430, height: height)
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { toggle() }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.backend?.terminate()
    }
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--check-json" {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let snapshot = try decoder().decode(Snapshot.self, from: data)
        print("decoded \(snapshot.tasks.count) tasks; running \(snapshot.tasks.filter { $0.status == "running" }.count)")
    } catch { fputs("\(error)\n", stderr); exit(1) }
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
