# AI Development Log

只追加有证据的开发检查点。记录时间、任务、基线 SHA、分支、变更文件、验证命令及结果、回滚方式和下一步。

## 2026-11-04 · AI 日志机制准备

- 原始分支：`main`。
- 基线提交：`59907aade9cddc44418c469d344c41bbbb52a30f`。
- 范围：仅仓库级开发规则、项目记忆、问题档案、日志说明和 Codex Hook 配置，不改业务源码、构建文件、生产服务或数据库。
- 已完成的离线验证：Python Hook 脚本语法与模拟的错误事件隐私过滤。
- 待验收：真实 Codex 工作区内 Hook 的信任、触发和本地 JSONL 写入；未将其标为已通过。

## 2026-11-09 · Router USB deletion

Baseline `cae70b34d84b163061ae8967eb8a02ef7125d14e`; branch `feat/ipad-router-usb-delete-0659`. iPad 0.6.59 successful Actions run 39690482361 used instead of stale 0.4.8 main. Native USB management view, session login, browsing, confirmation and verified delete response. Native build pending. Production USB not modified; current mount health and write policy unverified. No installation or deployment claimed. Rollback: keep original branch / disable deleteEnabled.

Build candidate: iPad 0.6.60 / build120. Files: RouterUSBManagement.swift, USBMovieLibrary.swift, TogetherPoCApp.swift, RouterUSBManagementTests.swift, project.yml. Native tests exercise read-only failure, mismatched acknowledgement, and verified success. `git diff --check` passed; Xcode is unavailable on this Linux executor, so use isolated GitHub Actions build. Production activation still requires actual disk checks; no remount implemented.
