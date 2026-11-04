# AI Development Log

只追加有证据的开发检查点。记录时间、任务、基线 SHA、分支、变更文件、验证命令及结果、回滚方式和下一步。

## 2026-11-04 · AI 日志机制准备

- 原始分支：`main`。
- 基线提交：`59907aade9cddc44418c469d344c41bbbb52a30f`。
- 范围：仅仓库级开发规则、项目记忆、问题档案、日志说明和 Codex Hook 配置，不改业务源码、构建文件、生产服务或数据库。
- 已完成的离线验证：Python Hook 脚本语法与模拟的错误事件隐私过滤。
- 待验收：真实 Codex 工作区内 Hook 的信任、触发和本地 JSONL 写入；未将其标为已通过。

## 2026-11-04 · Playback control baseline

- Branch: fix/playback-seek-clock-ipad-20261104; base: `5d117b58f6241f9ff9685b021c6ad76aaed1708d`. Clean before this task.
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

- First iPad CI: device compile passed and 55/55 selected core tests passed. UI test failed at app.launch with XCTest background assertion denied for the still-running unit-test host PID, before any seek interaction. Extracted xcresult diagnostics show no app crash report. Split core/UI invocations and explicitly terminate only the test simulator app between them; original UI assertions retained. Rerun pending.

- User added high-priority Android USB/HTTP compatibility phase after Seek/clock verification. Complete requirements preserved in TP-ANDROID-USB-HTTP-20261104; no router changes, source conversions or deployment performed.

- User added Android local-first / USB fallback requirements. Recorded TP-ANDROID-LOCAL-FIRST-20261104 for next phase jointly with USB compatibility. Preserve prior local binding/reconnect fixes, SAF permissions and per-device isolation; no whole-film upload or source mutation.

## 2026-11-04 · Verified Seek/clock checkpoint

- iPad app source `59487c6d146b653705cedd0d50b6837a35498de8`, Actions `41734096867` SUCCESS: unsigned device Release build, 55 core tests, 1 fullscreen real-movie seek UI test; baseline-vs-fixed policy and preserved recovery/EOF standalone checks passed. IPA 0.6.75 / 135, isolated app identity. SHA256 `732a047ece68599cadec83f04b2f75580d939bf0ac4ae379de6f1bdb4e1a4f0a`.
- Android app source `6363aad6709957ef6dd91c96b6951119124bd889`, Actions `41734109853` SUCCESS: 120 JVM tests, APK compilation, full 33-test emulator suite; additional three seek/clock/decoder checks passed on a fresh emulator. APK 0.6.60.7 / 127, isolated .fluency app identity, SHA256 `c934991e0a629bdac938084fd36b3a6add6b32d5a20d3f6b3d84234083aa896e`.
- Artifacts downloaded through authorized Actions access, ZIP digests and exact extracted hashes verified. Both installables saved; original app/services remain untouched. Android preview signing may differ from previous previews; never silently uninstall an existing app or promise same-signature upgrade.
- Review: draft PR30 (iPad), PR31 (Android) against each verified client baseline, no merge. Later workflow/docs commits do not change the verified application directories.
- Journal sync checked: AI Journal indexes main only (private a542f2c0136d342068855830f174df7bbf76814a; public c6d747298f4e9869292352107d7a45cb965bb36c). Task branches are committed on GitHub but not included in main-only MCP notes. Do not mark branch journal synchronization complete.
- Remaining acceptance: physical Android/iPad pair, real router/cloud long runs, timing across network failure. Backend wait-for-peer policy is unchanged and not claimed fixed. Original installed apps are the rollback; unsigned iPad requires user signing.

## 2026-11-04 · Reopen iPad seek reliability

- Baseline a4d00a46c7ec9eb06f627ac5e963acb978b2ca5d, iOS application tree matches 59487c6d146b653705cedd0d50b6837a35498de8 exactly. New branch fix/ipad-native-seek-slider-20261104, clean on entry.
- Additional run41734974307: 55 core tests pass, independent fullscreen UI reaches the real drag but remaining-time expectation and following subtitle checks fail. The earlier single successful UI run does not establish reliable seek. User informed not to install the 0.6.75 preview yet.
- Suspected deterministic race: SwiftUI Slider binding setter and onEditingChanged callbacks share a preview flag; a value delivered before begin can be replaced by the old playhead, while value-only accessibility adjustments can leave an editing flag latched. Replace with native UISlider explicit value/commit/cancel routing; preserve native clock display and AVPlayer seek acknowledgement.
- No test assertion removed. Native coordinator event-order/cancellation/accessibility regressions and the same real fullscreen test will run. Not yet compiled/verified.

## Native-slider run41739107694 actual result
- Device Release and 57 native tests passed. Fullscreen UI failed before Seek at initial subtitle assertion, then remaining/subtitle assertions; candidate not deliverable. AX snapshot showed the 12s fixture at EOF while controls had been prepared. Test fixture paused native player but retained localPlayIntent=true, permitting normal recovery to restart it.
- Update only DEBUG fixture setup to use intent-aware PAUSE and real SEEK to1s once tracks are available. Preserve original caption, remaining6/7, subtitle-panel and physical-slider assertions. No claim that this explains all prior Seek failures. Rerun pending.

## 2026-11-04 iPad0.6.76 verified candidate checkpoint
- Application/source6f26227ec5897e8f4a0bbd46d3273ffc016d0a6c, run41741956555 success: Release device build;57 native tests; actual fullscreen .2/.8/.5 progress gestures with remaining6/7 and subtitle adjustment assertions passed (one UI test,76s). Historic baseline reproduction/preserved recovery checks also passed. Earlier0.6.75 and failed41739107694 remain superseded and are not recommended.
- Artifact13281738313 archive digest1303c4a1c0a60b6bb981f2fa97321114f8049bd48523b270e40e14221b245578 verified after download. IPA17,649,137 bytes SHA2562384aef7a125ecc3522bf855ca3f6e1b0ec403932843e541fb70e3b9fa8b4eeb. Info.plist0.6.76/136, isolated dev.together.poc.asrtest, original comparison display name retained. Unsigned, requires compatible device signing.
- Physical iPad long playback/background/network/repeated-seek matrix and real two-device synchronization remain unverified; successful simulator run does not establish those results. No main merge or production install. Rollback remains the prior separately validated delivery; source snapshot at this commit is reviewable via PR33. Main-only AI Journal has not ingested this branch.

## 2026-11-04 · Leading-device wait candidate
- Baseline 8e283e492cb038e04c18e02a639b1793aaefbe52; independent leading-wait branch. Candidate only, no deployment or installation.
- Local ahead >10000ms pauses only this device; resume at <=1000ms ahead. Check latch before native-running gate; preserve manual SEEK, room PAUSE, question gates, offsets and source errors.
- Exclude intentional wait from stall recovery. Optional syncWaiting status is diagnostic; do not report it as buffering or a shared PAUSE.
- Regression/build pending; hardware pair and long playback unverified.

## 2026-11-04 · iPad leading-wait verified delivery
- Application734221933620a5656d72073be20ea6dc6ed1573a;0.6.77/137; Actions41807041334 SUCCESS: unsigned device Release build,61 targeted native tests0 failures,1 real fullscreen continuous-seek UI test0 failures. Baseline-vs-fixed and preserved standalone sync checks passed.
- Artifact13310304841 archive SHA256adb0c019be845c1f34acd3d190090e989c53013e0e43f9f1d0bb488c88d82448 verified against bytes. IPA17650075 bytes SHA2562364f6adef69dc8b8efc49c0eb42da21352b882264f6dba7f9c624689fe4b01f matches build checksum; Info.plist confirms0.6.77/137/dev.together.poc.asrtest. IPA requires user signing.
- Wait compares actual local position (including offset) to canonical room time, not another device's reported position. Pause locally above10000ms; resume within1000ms; explicit seek and shared pause override. Native-paused wait checked before startup-running gate; stall recovery excludes intentional wait. Ordinary server buffer-wait policy remains separate and unchanged.
- Android counterpart e2e2dad/0.6.60.9 passed141 JVM+38 native tests. Source-fault server counterpart separately authorized, backed up, deployed and protocol-tested locally and through public entry. No merge/client installation. Physical two-device playback and long hardware runs remain unverified. Previous candidates retained as rollback; branch logs committed, main-only AI Journal ingestion not claimed.

## 2026-11-04 · User correction supersedes automatic wait
- Latest user instruction: no automatic pause for ordinary drift or peer buffering; pause belongs to users; explicit SEEK goes to both. Historical smart-pause text was supplied as reference, subsequently superseded by this clarification. Remove the erroneous >10s automatic local pause.
- Candidate uses lag>5000ms continuously for5000ms, resets on brief recovery, invalid/gapped samples or buffering; normal speed within3000ms. Sustained duration awaits user preference; candidate default5s. Leading device keeps normal requested speed, no automatic backward SEEK/pause.
- Preserve verified manual SEEK confirmation, live clock, fullscreen native slider and Android local-first routing/reconnect/permission/identity/subtitle/audio behavior. Native regression/build pending for this candidate.

## 2026-11-04 · User confirms ten-second persistence
- Supersedes candidate5s duration: lag must be strictly>5000ms continuously for at least10000ms before local rate catch-up starts. A return to<=5000ms before activation clears the timer; active catch-up returns to1x within3000ms. No automatic pause. Manual SEEK remains immediate.
- Earlier5s-duration CI candidates are superseded, not final deliverables. Update native/standalone boundary and interruption tests; rerun required.
