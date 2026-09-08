# Mac 资源监控

每 15 秒取整机 CPU 差分、内存压力及前 15 项进程组。按最外层 App 路径汇总辅助进程；模拟器作为一组。进程 CPU 使用 ps 的近期平均值，100% 为一个核心，与整机 0–100% 不同。RSS 合计可能重复计算共享页，只作占用估算。

CPU ≥90% 或内存压力为 critical 持续 60 秒后弹窗，默认全部不勾选。只允许正常退出当前运行的普通 GUI 应用（Finder 除外）；后台任务、系统服务只展示。选中模拟器组会通过 simctl 正常关闭全部模拟设备。应用可以弹保存框或拒绝退出，绝不强杀。90 秒不操作关闭提示；两次提示至少间隔 30 分钟。弹窗为独立进程，不阻塞采样。睡眠或采样断档会重置持续时长。

安装：`python3 scripts/system/resource_watch/install.py`，随后 `~/Dev/jobs/ctl resume resource-watch`。更新编译后使用 `ctl reload resource-watch`。暂停：`~/Dev/jobs/ctl pause resource-watch`。

记录只存在本机 `~/Library/Application Support/ResourceWatch/`（目录权限 700）：

- `latest.json`：当前快照。
- `samples-YYYY-MM-DD.jsonl`：每次采样，自动保留 14 天。
- `actions.jsonl`：提示及用户请求退出记录；退出请求不是已退出证明。
- `config.json`：采样间隔、阈值、持续时长、冷却、保留天数；修改后 reload。

不收集命令参数、网页标题、文档内容。包含本机程序路径。退出确认后按原应用实例发请求，避免 PID 复用误杀。

验收入口：二进制 `--once` 采样一次后退出；`--preview` 显示真实快照，所有退出动作禁用（确认也不会退出应用）。正常监控无参数。
