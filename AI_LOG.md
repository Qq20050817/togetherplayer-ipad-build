# AI Development Log

只追加有证据的开发检查点。记录时间、任务、基线 SHA、分支、变更文件、验证命令及结果、回滚方式和下一步。

## 2026-11-04 · AI 日志机制准备

- 原始分支：`main`。
- 基线提交：`59907aade9cddc44418c469d344c41bbbb52a30f`。
- 范围：仅仓库级开发规则、项目记忆、问题档案、日志说明和 Codex Hook 配置，不改业务源码、构建文件、生产服务或数据库。
- 已完成的离线验证：Python Hook 脚本语法与模拟的错误事件隐私过滤。
- 待验收：真实 Codex 工作区内 Hook 的信任、触发和本地 JSONL 写入；未将其标为已通过。

## 2026-11-04 · Playback control baseline

- Branch: fix/playback-seek-clock-android-20261104; base: `5d8f195fb89d2730c00db1664d0c927abaff0612`. Clean before this task.
- Android verified Actions 40111478357, 0.6.60.6 / 126. iPad production 0.6.69 Actions 40030378042; newer isolated subtitle-comparison 0.6.74 / 134 Actions 40696932858 retained as iPad candidate baseline. Do not overwrite installed production identity.
- Private main a542f2c0136d342068855830f174df7bbf76814a contains older client sources. Server deployment identity unavailable while remote hosts are offline; no server change authorized by this checkpoint.
- Scope: manual seek acknowledgement, live UI time, automatic drift policy. Preserve existing subtitles, AI, local source bindings, HTTP recovery, P2P handoff and pause/question gates.
- Evidence: both SyncCore implementations auto-seek above 1500ms; iPad completion ignores finished; Android compatibility getter fabricates pending target up to 3s. Slider drag state and shared UI/sync callback require isolated regression.
- Recovery: discard these new branches/worktrees; existing branches and services untouched. Native tests not run yet.

- User refinement: automatic drift tolerance is 3000ms (updated from 5000ms). Explicit manual SEEK bypasses it. Catch-up settles within 1000ms to prevent rate flapping.

## 2026-11-04 · Seek/clock candidate

- Minimal client edits and new isolated CI workflows; no server, router or existing install changes.
- Seek: explicit room timeline discontinuities bypass tolerance, delayed preparation retains newest target, same-version snapshots cannot repeat jump, pending SEEK coalescing retains PLAY/PAUSE. iPad finished/position checks, one retry, 15s bounded deadline; Android actual playhead checks and 15s failure feedback.
- Clock: iPad native time observation plus common-mode watchdog, slider binding avoids accessibility drag latch and clears on disappearance; Android independent lifecycle clock and guaranteed sync repost, canceled drag reset, no fabricated VLC playhead.
- Auto correction: 3000ms tolerance; local speed catchup with no repeated automatic hard seeks. Existing explicit pause/question behavior retained.
- Validation so far: git diff --check; native compile/tests have not run. New matching cross-platform policy, seek burst, stale snapshot, loading/offset and failure tests ready for CI.
- Candidate iPad 0.6.75/135 preserves isolated .asrtest identity and 0.6.74 subtitle features; Android 0.6.60.7/127 preserves .fluency identity and HTTP 2008 recovery. Server wait-for-peer policy not changed or verified.
- Recovery: retain installed versions; do not merge branches or deploy server.
