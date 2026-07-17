# 更新日志

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## 1.1.1 — 2026-07-17

- 将仓库说明、macOS 应用与安装包的用户可见名称统一为 `CodeXMicro++`。
- 应用和安装包文件名改为 `CodeXMicro++.app` 与 `CodeXMicro++-1.1.1-universal.dmg`。
- 删除实体控制器插件、场景、管理工具及相关 Node.js 代码，仓库仅保留 macOS App。
- 保留 Bundle ID、签名目录与窗口状态键等技术标识，确保升级兼容。

## 1.1.0 — 2026-07-17

首个公开开源版本。

### macOS 虚拟控制面板

- 原生 SwiftUI 4 × 4 悬浮面板，支持移动、等比例缩放、跨桌面与始终置顶。
- 最近 6 个 Codex 任务的实时状态与一键跳转。
- 四向任务摇杆、四档推理旋钮、Fast、同意、拒绝、新任务和按住说话。
- CodeX 状态键显示本周剩余 Token 与累计消耗，约每 20 秒刷新。
- 可搜索的分类工具箱，覆盖任务、代码、Git、导航、界面与常用工作流。
- Force Touch 触觉强度、机械按键音与辅助功能权限设置。

### 分发

- Apple Silicon / Intel 通用 DMG。
- SHA-256 校验文件。
- MIT License 与完整源码。
