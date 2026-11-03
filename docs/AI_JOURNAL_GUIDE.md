# AI 开发记忆与 Codex 事件日志

本项目使用以下各自分工的记录：
- `AGENTS.md`：每次开发前检查、变更边界和验收规范。
- `AI_MEMORY.md`：长期有效的决策和不可破坏的行为。
- `AI_ISSUES.md`：有复现证据的错误、原因、处理和回归状态。
- `AI_LOG.md`：可追溯的开发检查点，包括 commit、测试与回退步骤。
- `.ai/logs/codex-events.jsonl`：本机 Codex Hook 事件元数据，已忽略 Git。

Hook 会在 SessionStart、PostToolUse、Stop、Interrupt 时记录少量元数据，不保存工具输入输出、命令正文或用户数据。工具失败时 Hook 也应尽力运行，但它不是完整审计系统。

使用方法：
1. 在本地检出含本配置的分支，安装 Python 3 与 Git。
2. 用 Codex 打开该项目，执行 `/hooks` 审核并信任项目级 Hook。未审核前可能被跳过。
3. 进行一次安全的只读命令，检查 `.ai/logs/codex-events.jsonl` 是否记录对应事件。
4. 每个有效开发检查点由 AI 将实际结果追加至 `AI_LOG.md`，再通过独立分支提交这些 Markdown 记录。

远程 ChatGPT 会话、部分云环境以及缺少项目文件访问权限的工具可能无法执行本地 Hooks。跨设备持久记录依靠已提交的 Markdown 文件与 Git 历史。日志目录默认不上传，避免公开敏感信息。

发生分支冲突或存在未提交改动时先检查并保留，不允许自动覆盖。若需要关闭 Hooks，可在 Codex 的 `/hooks` 停用，或在相应受控配置中设置 `[features] hooks = false`。
