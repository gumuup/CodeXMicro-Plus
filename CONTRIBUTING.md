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

本仓库采用 [PolyForm Noncommercial License 1.0.0](LICENSE) 与单独商业许可并行的双重授权模式。为确保项目所有者可以继续为完整项目提供商业授权，第三方代码贡献在合并前必须另行完成贡献者授权确认。未经确认的第三方代码不会合并；提交 Issue、问题复现和不包含受版权保护代码的建议不受此限制。准备提交代码前，请先通过 README 中的联系方式与维护者确认。
