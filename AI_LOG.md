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

- CI checkpoint: iPad baseline reproduction and fixed-policy standalone test passed in Actions 41733594267 at commit b2cc83a5552016fa186131fc4b3d8f8a8491a01d. Android Actions 41733599767 at fe20d1d0c037e53594ae1eaa460bd7a6ce8ff5a7 started. Full native build pending. Follow-up tightens native confirmation to 250ms and restores historical recovery checks alongside new policy suite.

- First Android CI: 120 JVM unit tests ran, 119 passed; pauseCancelsPlayIntentEvenWhilePlayerNotReady failed. Root: new explicit-seek waiting gate returned before honoring paused intent when decoder was unready. Fixed on both platforms by applying PAUSE before the readiness gate; original assertion preserved. Android source/test compilation passed; native emulator tests not reached.

- User added high-priority Android USB/HTTP compatibility phase after Seek/clock verification. Complete requirements preserved in TP-ANDROID-USB-HTTP-20261104; no router changes, source conversions or deployment performed.

- User added Android local-first / USB fallback requirements. Recorded TP-ANDROID-LOCAL-FIRST-20261104 for next phase jointly with USB compatibility. Preserve prior local binding/reconnect fixes, SAF permissions and per-device isolation; no whole-film upload or source mutation.

## 2026-11-04 · Verified Seek/clock checkpoint

- iPad app source `59487c6d146b653705cedd0d50b6837a35498de8`, Actions `41734096867` SUCCESS: unsigned device Release build, 55 core tests, 1 fullscreen real-movie seek UI test; baseline-vs-fixed policy and preserved recovery/EOF standalone checks passed. IPA 0.6.75 / 135, isolated app identity. SHA256 `732a047ece68599cadec83f04b2f75580d939bf0ac4ae379de6f1bdb4e1a4f0a`.
- Android app source `6363aad6709957ef6dd91c96b6951119124bd889`, Actions `41734109853` SUCCESS: 120 JVM tests, APK compilation, full 33-test emulator suite; additional three seek/clock/decoder checks passed on a fresh emulator. APK 0.6.60.7 / 127, isolated .fluency app identity, SHA256 `c934991e0a629bdac938084fd36b3a6add6b32d5a20d3f6b3d84234083aa896e`.
- Artifacts downloaded through authorized Actions access, ZIP digests and exact extracted hashes verified. Both installables saved; original app/services remain untouched. Android preview signing may differ from previous previews; never silently uninstall an existing app or promise same-signature upgrade.
- Review: draft PR30 (iPad), PR31 (Android) against each verified client baseline, no merge. Later workflow/docs commits do not change the verified application directories.
- Journal sync checked: AI Journal indexes main only (private a542f2c0136d342068855830f174df7bbf76814a; public c6d747298f4e9869292352107d7a45cb965bb36c). Task branches are committed on GitHub but not included in main-only MCP notes. Do not mark branch journal synchronization complete.
- Remaining acceptance: physical Android/iPad pair, real router/cloud long runs, timing across network failure. Backend wait-for-peer policy is unchanged and not claimed fixed. Original installed apps are the rollback; unsigned iPad requires user signing.
