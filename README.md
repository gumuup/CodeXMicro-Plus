# CodeXMicro++

![CodeXMicro++ 虚拟控制面板](Sources/CodeXMicroApp/Resources/CodeXMicroHardware.png)

一款为 Codex 桌面端设计的开源 macOS 悬浮控制面板。

CodeXMicro++ 把任务切换、Plan / Goal 模式、推理强度、Agent 状态、Token 用量和常用工作流放到一块始终置顶的 4 × 4「微型键盘」里。应用完全在本机运行，不上传任务、按键或 Token 数据。

> 非 OpenAI 或 Work Louder 官方产品。Codex、OpenAI 等名称及标识归各自权利人所有。

## 下载与安装

前往 [Releases](https://github.com/gumuup/CodeXMicro-Plus/releases/latest) 下载最新版：

- `CodeXMicro++-1.1.3-universal.dmg`：macOS 通用安装包，支持 Apple Silicon 与 Intel Mac。
- `.sha256`：对应文件的 SHA-256 校验值。

系统要求：

- macOS 14 或更高版本
- 已安装 Codex 桌面应用
- 控制 Codex 时需要授予 macOS「辅助功能」权限

安装步骤：

1. 打开 DMG，把 `CodeXMicro++.app` 拖入「应用程序」。
2. 当前安装包未经 Apple 公证。首次启动时，请在 Finder 中按住 Control 点击应用并选择「打开」。
3. 按提示前往「系统设置 → 隐私与安全性 → 辅助功能」，允许 CodeXMicro++。
4. 重新打开应用。它会显示在桌面悬浮层和菜单栏中。

为确保 Fast、Plan 和推理强度等快捷操作可用，请把 [`codex-keybindings.json`](codex-keybindings.json) 中的条目合并到 `~/.codex/keybindings.json`，并保留你原有的自定义快捷键。

辅助功能权限只用于向本机 Codex 发送你主动触发的快捷键。

## 功能说明

### 左上角摇杆

| 操作 | 功能 |
| --- | --- |
| 向左推 | 切换到上一个任务 |
| 向右推 | 切换到下一个任务 |
| 向上推 | 开启或关闭 Plan 计划模式 |
| 向下推 | 进入 Goal 目标模式，在输入框预填 `/goal `，等待输入目标后发送 |

### 右上角推理旋钮

- 点击左半边：降低推理强度。
- 点击右半边：增加推理强度。
- 也支持上下拖动或双指滚动。
- 强度分为轻度、中、高、极高四档，并带有刻度反馈。

### Agent 状态键

中间 6 个透明键显示最近的 6 个 Codex 任务：

- 蓝色：正在运行
- 黄色：等待输入
- 绿色：已完成
- 红色：出现异常
- 灰色：空闲

点击任意状态键会直接打开对应的 Codex 任务。

### CodeX 键

- Codex 未运行时：点击启动并跳转到 Codex。
- Codex 运行后：后台约每 20 秒刷新本周剩余 Token 比例与累计 Token 消耗。
- 单击按键：在「本周剩余」和「累计消耗」之间切换。
- 周剩余额度会以绿色、橙色、红色圆环提示余量。

### 工具箱

按右上角工具箱图标，可以搜索并执行完整的 Codex 快捷操作，按「常用、任务、代码、Git、工具、导航、界面」分类，包括：

- Fast、同意、拒绝、发送、新任务、分叉、Plan、语音听写
- 任务搜索、任务内查找、归档、置顶、复制 Markdown
- Review、Terminal、调试、测试、重构、理解代码库、界面打磨
- Git 状态、提交、分支、合并、创建 / 审查 Pull Request、验证并推送
- 浏览器、文件、图片、OpenAI 文档、Skills、定时任务、插件
- 命令菜单、前进后退、侧边栏、底部面板、字体与推理强度

其中「一键工作流」会在新任务中填入经过整理的中文提示词并执行。

### 其他按键与交互

- `FAST`：切换 Fast 模式。
- `同意 / 拒绝`：响应 Codex 的确认请求。
- `新任务`：创建 Codex 任务。
- 麦克风：按住说话，松开发送。
- 左下圆形触控键：显示或隐藏按键文字。
- 设置：调整 Force Touch 触觉强度与机械按键音，检查辅助功能权限。
- 拖动面板顶部或底部可移动；拖动四角可等比例缩放（300–700 px）。
- 菜单栏可显示、隐藏或退出悬浮面板；`⌥⌘M` 可快速切换显示状态。

## 隐私与安全

CodeXMicro++：

- 从 `~/.codex/state*.sqlite` 和本地 rollout 文件读取最近任务状态。
- 通过本机 Codex 命令读取 Token 用量，并限制为约 20 秒刷新一次。
- 不包含遥测、广告或第三方分析 SDK。
- 不上传任务内容、按键记录或账户用量。
- 不会把本机开发签名私钥写入项目目录。

公开代码不等于已经经过独立安全审计。发现安全问题请遵循 [SECURITY.md](SECURITY.md) 中的私密报告方式。

## 从源码构建

需要 Xcode Command Line Tools 和 Swift 6：

```bash
git clone https://github.com/gumuup/CodeXMicro-Plus.git
cd CodeXMicro
./script/build_and_run.sh --verify
```

首次本地构建会在 `~/Library/Application Support/CodexMicro/Signing/` 创建仅用于开发的独立签名钥匙串。后续构建沿用同一身份，避免每次重新授权辅助功能；私钥始终位于项目目录之外。

常用命令：

```bash
./script/test_native.sh       # 运行原生逻辑测试
swift build                   # 编译 SwiftPM 应用
./script/package_dmg.sh       # 构建 universal DMG
```

## 项目结构

```text
Sources/CodeXMicroApp/             原生 SwiftUI macOS 应用
tests/                             Swift 原生逻辑测试
script/                            构建、签名与 DMG 打包脚本
codex-keybindings.json             Codex 快捷键配置
```

## 参与贡献

有任何关于产品的新灵感或想法，欢迎联系作者本人 @谷木：

- 微信：`gumuup`
- 邮箱：[1142929785@qq.com](mailto:1142929785@qq.com)

欢迎提交 Issue 和 Pull Request。开始前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

版本变化记录见 [CHANGELOG.md](CHANGELOG.md)。

## 许可证

本项目采用 [MIT License](LICENSE) 开源。
