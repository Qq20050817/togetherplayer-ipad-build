# AI Development Log

只追加有证据的开发检查点。记录时间、任务、基线 SHA、分支、变更文件、验证命令及结果、回滚方式和下一步。

## 2026-11-04 · AI 日志机制准备

- 原始分支：`main`。
- 基线提交：`59907aade9cddc44418c469d344c41bbbb52a30f`。
- 范围：仅仓库级开发规则、项目记忆、问题档案、日志说明和 Codex Hook 配置，不改业务源码、构建文件、生产服务或数据库。
- 已完成的离线验证：Python Hook 脚本语法与模拟的错误事件隐私过滤。
- 待验收：真实 Codex 工作区内 Hook 的信任、触发和本地 JSONL 写入；未将其标为已通过。

## 2026-11-04 · Android / iPad 安装包下载入口恢复

- 目标：恢复用户无法打开的 Xiaomi Pad 7 APK 0.6.60.11 与 iPad IPA 0.6.78 下载入口；不修改业务代码或线上服务。
- 仓库检查：`main` 基线 `c6d747298f4e9869292352107d7a45cb965bb36c`，不作为最新客户端源码；文档工作分支 `docs/download-recovery-20261104`。
- Android 成功构建：Actions run `41817230504`，分支 `delivery/android-pad7-arm64-20261104`，提交 `78ea8306d6a723bc221ae15262423cbe0b9b8476`，artifact `13316215327`。提取 `TogetherPlayer-Xiaomi-Pad7-0.6.60.11.apk`，78,557,417 字节，SHA-256 `4eb4e200fc0fec63b575ff144c4e558f65ef995787c541ece08dbe1ea3aa269b`。
- iPad 成功构建：Actions run `41812241613`，分支 `fix/ipad-smart-pause-20261104`，提交 `4d6e880574307442811bca925966bd71ac2308dc`，artifact `13313537141`。提取 `TogetherPlayer-iPad-0.6.78-Seek-Clock-unsigned.ipa`，17,650,574 字节，SHA-256 `5d366f82485a19903f894ebf81f51359f1793a7cf0e20a353f6a2b890ac66992`。
- 验证：两项 Actions 均显示 success；下载解包成功，两个单文件 SHA-256 均与对应 artifact 内 `SHA256SUMS.txt` 一致。用户手机上的下载与真机安装尚未确认。
- 交付：直接 `.apk` 与未签名 `.ipa` 文件，避免要求用户下载 ZIP；交付副本已保存为可再次下载的文件。
- 修改文件：仅本分支 `AI_LOG.md`、`AI_ISSUES.md` 文档。恢复：舍弃文档分支即可；客户端回溯以原 Actions run 和精确 SHA 为准，不影响任何正式服务。
- 待跟进：验证用户端是否能打开新链接和安装；此前链接无法加载的根因尚未证实。
