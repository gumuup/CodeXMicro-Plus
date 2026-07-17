# 参与贡献

感谢你帮助改进 CodeXMicro++。

## 开始之前

1. 先搜索现有 Issue，避免重复工作。
2. 修复缺陷时，请说明复现步骤、macOS / Codex 版本及预期行为。
3. 较大的功能改动建议先创建 Issue 讨论交互和兼容性。

## 本地开发

```bash
git clone https://github.com/gumuup/CodeXMicro-Plus.git
cd CodeXMicro
swift build
./script/test_native.sh
```

运行原生应用：

```bash
./script/build_and_run.sh --verify
```

## 提交 Pull Request

- 一个 PR 聚焦一个目的，提交信息使用简短的祈使句。
- 不要提交 `.build/`、`dist/`、本机数据库、签名证书或密钥。
- 行为变化应补充或更新测试与 README。
- 提交前运行 `swift build` 和 `./script/test_native.sh`。
- UI 改动请附上截图，并验证面板最小与最大尺寸。

贡献者提交代码即表示同意其贡献按本仓库的 MIT License 发布。
