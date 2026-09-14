# Mac 资源监控

每 15 秒取整机 CPU 差分、内存压力及前 15 项进程组。进程使用相邻采样的累计 CPU 时间差；100% 单核代表一个逻辑核心，同时展示除以逻辑核心数后的整机占比。整机与进程窗口长度分别记录，采集不是原子操作，数值不要求精确相加。

后台任务按既有 jobs 控制器的 launchd Label 和 PID/PPID 链归属，深层子进程算入所属任务，每个 PID 只计一次。其余进程按最外层 App 路径汇总，模拟器作为一组。记录前 15 个高 CPU 进程的 PID、父链、启动时间，以及所有采样中识别到的运行任务，避免多个 Python 任务混为一组。没有 PID 的等待任务不算正在执行。

首次出现、PID 重用、计数回退的进程要到下次可比采样才计 CPU；已退出或两次采样之间完成的进程无法完整测量。覆盖数字明确记录，含未测量进程的组以 `≥` 显示已知部分。父链只作归属证据，不重复累加子树；JSON 的 top、top_processes、managed_jobs 是不同视图，不能跨列表相加。RSS 合计可能重复计算共享页，只作占用估算。历史旧日志缺少 PID，不能靠当前进程树补写过去的任务归属。

CPU ≥90% 或内存压力为 critical 持续 60 秒后弹窗，默认全部不勾选。只允许正常退出当前运行的普通 GUI 应用（Finder 除外）；后台任务、系统服务只展示。选中模拟器组会通过 simctl 正常关闭全部模拟设备。应用可以弹保存框或拒绝退出，绝不强杀。90 秒不操作关闭提示；两次提示至少间隔 30 分钟。弹窗为独立进程，不阻塞采样。睡眠或采样断档会重置持续时长。

安装：`python3 scripts/system/resource_watch/install.py`，随后 `~/Dev/jobs/ctl resume resource-watch`。已有安装更新用 `install.py --build-only`，仅原子替换二进制，保留 plist 和 config；再用 `~/Dev/jobs/ctl reload resource-watch` 只重载监控本身。暂停：`~/Dev/jobs/ctl pause resource-watch`。

记录只存在本机 `~/Library/Application Support/ResourceWatch/`（目录权限 700）：

- `latest.json`：当前快照。
- `samples-YYYY-MM-DD.jsonl`：每次采样，自动保留 14 天。
- `actions.jsonl`：提示及用户请求退出记录；退出请求不是已退出证明。
- `config.json`：采样间隔、阈值、持续时长、冷却、保留天数；修改后 reload。

不收集命令参数、网页标题、文档内容。包含本机程序路径。退出确认后按原应用实例发请求，避免 PID 复用误杀。

只读诊断：二进制 `--diagnose 2`（可选 1–60 秒）向 stdout 输出 JSON，不写状态、取 daemon 锁或显示界面。可与单个常驻监控并行，不会成为第二个常驻监控。`--once` 会写一次真实快照后退出；`--preview` 显示真实快照，所有退出动作禁用（确认也不会退出应用）。正常监控无参数。

回归：`swiftc ProcessSampling.swift tests/main.swift -o /tmp/resource-watch-tests && /tmp/resource-watch-tests`（在本目录运行）。覆盖多层任务归属、不同 Python 任务、CPU 差分、PID 重用、未测量覆盖和重复计数。
