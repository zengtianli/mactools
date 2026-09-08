# 资源监控 · 2026-09-09

用户要求低占用常驻监控，持续过载后询问是否退出高占用 App，接入 jobs。

实现：`scripts/system/resource_watch/main.swift`；安装 `install.py` 编译原生 App 到忽略的 build，plist 原版 `deploy/com.tianli.resource-watch.plist`，LaunchAgents 软链接。已通过 jobs ctl 加载。

15 秒采样，CPU 90% / critical 内存压力持续 60 秒，30 分钟冷却，弹窗 90 秒自动取消。每应用 CPU/RSS 汇总，模拟器集中显示；默认不选，用户确认才正常退出。系统服务不可勾选；不强杀。记录目录和调参见实现 README。

已验证 Swift 编译、--once 实测采样、launchd 运行、原生预览的 AX 内容（应用可选/系统禁用）。未为验收强行关闭用户正在运行的应用；真实应用退出/拒绝保存分支尚未端到端验证。CUA 在关闭预览时超时，提示自身有 90 秒取消机制。首次运行实测常驻约 10 MB、ps CPU 0.0%，非长期峰值保证。
