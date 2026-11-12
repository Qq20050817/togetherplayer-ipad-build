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

## 2026-11-04 · iPad background room reconnection candidate
- User report: iPad 0.6.78 reconnect fails after app backgrounding, UI indicates connection interrupted. Android counterpart unconfirmed and unchanged.
- Verified application baseline: 4d6e880574307442811bca925966bd71ac2308dc, Actions 41812241613 SUCCESS, iPad 0.6.78/138. New isolated branch: fix/ipad-room-background-rejoin-20261104.
- Source inspection: RoomEnvelope.decode discarded all valid JSON frames larger than 8192 bytes. Reconnected WELCOME may include room history; a discarded WELCOME leaves the room disconnected until heartbeat timeout. Scene active handler skipped stale foreground socket states.
- Changed ios/TogetherPoC/RoomTransport.swift and ios/TogetherPoC/TestClient.swift to accept bounded 1 MiB room frames and renew stale session on activation while retaining fresh handshakes. Added iOS native tests for large WELCOME after background, malformed/oversized frame and resume decision. Bumped isolated iPad candidate to 0.6.79/139; updated CI verification and unsigned packaging.
- Production server remained untouched. Read-only checks: Singapore TogetherPlayer process running and local /health HTTP 200, public TogetherPlayer endpoint reachable (root 404 expected); room-specific auth/lease logs were not accessible, server-side contribution not excluded.
- Verification: GitHub Actions run 41833322017 started on commit c0c7e6dc23980883c78b5972785b01b16dd4ebbf, pending result. Device lifecycle and two-device field test unverified. No install, merge or deployment.
- Recovery: retain existing 0.6.78 IPA and application baseline SHA; revert candidate branch to 4d6e880574307442811bca925966bd71ac2308dc. Do not uninstall user's signed app or delete data.

### Follow-up evidence correction (same session)
- Private Go backend server/internal/backend/server.go trims WELCOME history to <=7800 bytes where possible, and server_test.go verifies reconnect using the original credential after disconnection. Thus a normal server WELCOME >8192 bytes is not established; the new bounded envelope allowance is defensive. The exact field root cause remains unconfirmed.
- Client UI text "连接中断，自动重连" originates in TestClient.reconnect. Scene-active stale-socket resume remains the primary iPad candidate. User-side frames, HTTP status and lifecycle trace remain unavailable; no field-tested claim.

### CI and artifact verification (2026-11-04, same independent branch)
- Three identical-app-source GitHub Actions candidates: 41833322017 and 41833455531 FAILED solely in legacy AudioSubtitleTests.testMKVRemuxExposesEmbeddedAudioAndSubtitleGroups (two missing timed-cue display assertions); all 14 RoomConnectionTests passed. No changes made to weaken or bypass the legacy test.
- Run 41833459657 SUCCESS: unsigned iPad device Release build, 76 selected native tests (including 14 RoomConnectionTests and all AudioSubtitleTests), real fullscreen seek UI test, IPA packaging and artifact upload. The two previous failures indicate possible simulator subtitle playback flakiness, not a proven regression of the reconnect patch; continue monitoring.
- Verified deliverable: TogetherPlayer-iPad-0.6.79-Room-Resume-unsigned.ipa, SHA256 574eabaeef99ba529577e9713e5de4a9ea46a9e148bcc1d8c2a7f2923be24056, ZIP integrity passed; workflow artifact 13324104572 at run 41833459657.
- Branch remains isolated, no merge, iPad signing/install or live server deployment. Android unchanged. Two-person physical iPad background/rejoin acceptance and precise server-side per-room trace are not yet verified. Keep signed 0.6.78 for safe rollback, retaining application data.

### 2026-11-04 · iPad 0.6.79 Mainland HTTP delivery, no app change
- User cannot open ChatGPT sandbox link and requests fast mainland HTTP direct download. Reused verified unsigned 0.6.79/139 IPA (SHA256 574eabaeef99ba529577e9713e5de4a9ea46a9e148bcc1d8c2a7f2923be24056, 17650754 bytes), no rebuild.
- Connected to authorized OpenWrt Muse Bridge on GL-MT3000. Existing USB /mnt/sda1 had 82.6 GiB available; IPv6 public media HTTP port 49185 returned 204 at /health from Singapore.
- Transferred GitHub CI artifact 13324104572 into router staging, extracted only IPA into /mnt/sda1/Installers, independently verified SHA256. Removed staging ZIP after successful extraction; retained IPA.
- Backed up /etc/together-media/config.json to /etc/together-media/config.json.bak-pre-ipad079-20261104 and atomically added one allowlisted media item tp-ipad-079. Preserved previous eight config entries unchanged; service dynamically reads config, so no restart, route or firewall change. No passwords or signed URL recorded.
- Signed time-limited 168-hour direct HTTP path on usb-media.xiaokai123.de5.net:49185. Remote check: HTTP 200, application/octet-stream, Content-Length 17650754, Accept-Ranges; a 1 MiB Range request returned 206; full remote SHA256 matched. Cross-border Singapore sample speed only ~276 KB/s; actual mainland hotspot throughput remains unmeasured and should be reported by user.
- Existing config check found one original listed media file present and seven historical entries absent, corresponding to original HEAD 200/503 statuses. These original entries and film data were not modified. Avoid attributing historical stale entries to delivery change.
- Rollback of new public delivery only: restore backed-up config after checking intervening edits, remove exact IPA /mnt/sda1/Installers/TogetherPlayer-iPad-0.6.79-Room-Resume-unsigned.ipa once user no longer needs it. Never roll back media server/film services wholesale.

## 2026-11-04 · iPad foreground WebSocket reconnection, candidate 0.6.80

- User reopened persistent background/foreground room reconnection failure after 0.6.79 candidate. Exact installed build and actual WebSocket error code remain unknown.
- Source baseline: `fix/ipad-room-background-rejoin-20261104` HEAD `3af73989c37b78fc5ea0a0131a215480aeacc8dd` (documentation-only follow-up); application test and IPA baseline `f1e768e703c88fc99e6c1f67bc420b08d015f386`, Actions 41833459657 SUCCESS, unsigned 0.6.79/139.
- New independent branch `fix/ipad-foreground-ws-recovery-20261104` with no original source or production service overwritten. Changed `ios/TogetherPoC/RoomTransport.swift`, `TestClient.swift`, `TogetherPoCApp.swift`, `ios/NativeTests/RoomConnectionTests.swift`, `ios/project.yml`, and `.github/workflows/ipad-seek-clock.yml`.
- Purpose: preserve same room identity across application resume; reconnect after prolonged inactive scene; retire URLSession WebSocket transport state on every retry; show sanitized transport failure types; add a visible retry action; build an unsigned 0.6.80/140 candidate. The actual server/network cause is not yet proven.
- Before native CI: `git diff --check` passed, workflow YAML parsed. Local environment has no Swift/Xcode toolchain. Native app build, XCTest and physical iPad test remain **pending** and must not be called successful.
- Singapore read-only service `/health` HTTP 200; per-room telemetry and DB inaccessible (permission denied). No server, database, router, Android, signing or production changes.
- Rollback: previous 0.6.79 artifact and exact `f1e768e703c88fc99e6c1f67bc420b08d015f386` app baseline remain available. Do not uninstall user's signed app or clear room settings. CI result, commit and delivery must be appended after actual verification.

## 2026-11-05 · iPad0.6.83 room continuity candidate
- User confirms installed0.6.80 and requests fixing intermittent room disconnect/P2P fallback stutter; Android occurrence remains unconfirmed. Verified baselinec516a142790db11ca2febf71776c0c625e9efecc, successful41841128744. Isolated fix/ipad-room-transport-continuity-083-20261105; preserve existing room identity, source/subtitle, sync thresholds, manual controls and background pause. Do not import uncompiled TLS0.82 or undeployed peer-stall changes.
- Reproduced JavaScript bug from actual bundled P2P transport: DataChannel.open followed by PeerConnection.connected emits connected and downgrades native channel state, permitting repeated15s restarts. Current state-order/fallback/recovery/stale-generation regression passes after channel-aware status normalization; baseline fails the same assertion. Add bounded15/30/60/120s retry backoff. This proves a client defect, not the cause of every physical disconnect.
- Existing foreground policy reconnects after3s inactive even with100ms-old room traffic; now use actual socket/message/handshake freshness. Genuine foreground reconnect may retain already-ready playing media/room clock for a single identity-bound8s window; retries do not renew it, expiry pauses, same-source WELCOME avoids reload/reset/seek, paused/buffering/pending controls/blocking questions do not qualify. Offline user PAUSE immediately pauses and carries only to the same room/media after calibration. Background/leave/auth failure retain pause/cleanup.
- Candidate0.6.83/build143 adds safe numeric receive/close diagnostics, native policy/P2P-backoff and real AVPlayer item/clock/manual-pause tests with generated synthetic fixture. Local JS baseline reproduction and corrected JS tests pass; diff/YAML checks pass. Apple native compilation/physical network acceptance still pending; no IPA or field-fix claim. No router/backend/config/restart or trust change.

- User clarified the acceptance criterion is preventing actual unintended room disconnection during viewing, not masking it with continued video.8s grace is secondary mitigation only. Added a direct prevention fix: a missing operation ACK after12s must expire that command and request SYNC, not close an otherwise live WebSocket. Existing baseline health test explicitly reproduces that false disconnect with fresh room traffic. Retain real receive/send errors and welcome/message-silence recovery. Add injected monotonic clock plus controller tests for healthy-room ACK timeout and actual AVPlayer pause at grace expiry. Numeric transport diagnostics remain necessary for external network failures. Production proxy read-only check found no configured stream/read/write timeout in the Together route and no recent reload event matching this report; this does not exclude home Wi-Fi/TLS path.

- Additional diagnostic correction: HTTP101 is a successful WebSocket upgrade and must not hide subsequent NSError receive failures. Preserve readable network/TLS cause and numeric close/error telemetry without logging raw descriptions or tokens. No TLS fallback or trust override. Added protocol101 redaction regression. Home router IPv4 andIPv6 synthetic-room probes both establish trusted TLS1.3;180s hold test is running, not an iPad Wi-Fi test or a long-term stability claim.

- Corrected test-fixture project wiring against the official XcodeGen Target Source spec: generated MP4 is an explicit source entry with buildPhase:resources, not an unsupported target resources key. Add generated-project presence validation before compilation. Application source remains de0932d; native tests require rerun with the fixture actually bundled.
- Controlled network probe completed: with PLAYER_STATUS heartbeat and swapped roles, IPv4 guest360.2s/135 PONG+SYNC and IPv6 host360.8s/130 PONG+SYNC both stayed connected; synthetic room closed and maintenance lease ended. Earlier no-PLAYER_STATUS IPv6 guest EOF at134s remains inconclusive and must not be claimed as an IPv6 root cause. Local Caddy inspection did not locate the actual public Together route (Cloudflare endpoint); the previous absence-of-timeouts note is not proof of public-route configuration. No network settings or backend changed.

- Final transient-P2P refinement while the resource-corrected build remained pending: after an open channel drops, anchor the first15s recovery interval to that drop rather than an hours-old initial offer. This avoids immediately destroying a recoverable peer connection at the next roster update. Add boundary coverage; keep backoff and data-channel ordering regression. Also retain numeric send NSError codes/hints, since send failure can win the generation race with receive failure. No changes to network/timeouts/trust or playback thresholds.

## 2026-11-05 · Final scope follows no-disconnect clarification
- User explicitly wants room connectivity to remain stable while viewing; temporary continued playback is not the acceptance criterion. Remove the extra8s playback-grace/offline-pause mechanism and only its generated AVPlayer fixture from this release. Existing fixture files remain intact. Restore baseline NativeTests resource discovery. Genuine transport failure/background pause/source handling stays as the verified0.80 baseline. Earlier grace-candidate notes are superseded.
- Final changes directly prevent confirmed client-triggered disconnects: healthy sockets are not reset solely for3s inactivity or a missing12s command ACK; an expired command requests SYNC without stale replay. Keep P2P DataChannel ordering normalization, status deduplication, fresh15s recovery interval after transient channel loss and bounded15/30/60/120s renegotiation backoff. Include safe numeric send/receive/close diagnostics beneath successfulHTTP101. Clock injection supports actual controller ACK-timeout tests; existing playback/source/sync regressions remain required.
- Latest device/native verification must cover this narrowed scope. No network/backend/service/DNS/TLS policy changes. Synthetic route probes and maintenance leases have ended; full-heartbeat6min IPv4/IPv6 controls pass and do not establish a physical Wi-Fi root cause. The preceding trimming script stopped while refusing to remove a pre-existing nonempty fixture directory; this follow-up completes only project/log cleanup and preserves its existing contents.

## 2026-11-05 · First final native result and unchanged-code ARM verification
- b57eb8c run42012686373 attempt1 compiled unsigned device Release successfully. Native86 tests:85 pass,1 failure in pre-existing AudioSubtitleTests.testMKVRemuxExposesEmbeddedAudioAndSubtitleGroups line63 (early AVPlayer subtitle selection). All17 RoomConnectionTests and10 P2PFastPathGateTests pass, including healthy-room command timeout and P2P backoff. Full workflow remains FAILED; no IPA release claim. The same legacy MKV test has prior recorded intermittent failures; no subtitle assertion or implementation is weakened.
- Failed-job rerun was requested, then choose a fresh verification run on macos-15 ARM, matching the successful0.80 delivery environment. Current same-source P2P standalone ARM jobs have acquired runners and passed. This checks environment-sensitive AVPlayer timing without changing app code or assertions. Add run_attempt to artifact names so later reruns preserve failed logs and cannot conflict with an immutable earlier artifact.
- Read-only wireless inspection: iPad lease maps to5GHz, authenticated/associated, signal-57dBm; radio configured auto/HE160. No matching iPad disassociation/deauth/DFS/channel-switch event in the inspected log window. This snapshot does not exclude historical wireless issues; no radio or network settings changed. Maintenance lease ended normally.

## 2026-11-05 · iPad0.6.83 verified stability build
- Final application/native-test sourceb57eb8cd39a1380c14c84f63652fb2a2b74709bb; final ARM workflowbeb719c1a81e339bc6cea07ff62dc74b727ef258 (app/tests byte-equivalent). Run42016927669 SUCCESS: unsigned iOS device build,86 native tests0 failures and actual fullscreen progress/movie-adjustment UI test PASS. All17 RoomConnectionTests and10 P2PFastPathGateTests pass. Node packaged-state ordering and independent Swift P2P/Muse handoff pass. Keep first Intel run42012686373 failure in the existing early-subtitle-selection test recorded; no assertion was weakened or skipped.
- Concrete prevention: a missing12s operation ACK no longer closes a healthy room; brief inactive scenes with fresh traffic no longer force reconnect. Correct an open DataChannel being downgraded by a later connected event; allow transient channel recovery before bounded15/30/60/120s renegotiation. Genuine transport failure/background pause retain0.80 behavior. No8s playback workaround, source/subtitle/sync threshold or server/network policy change. Actual continuous-viewing resolution on the user's iPad remains OPEN until installed and observed.
- Artifact13410148385 archiveSHA256eacf137c175868ef67ef1e7748d27ed884c4a7ef7bebd01722b096b6bfc2cc2e. Verified unsigned0.6.83/build143/dev.together.poc.asrtest, iOS-device ARM64 Mach-O platform2, bundled P2P resource matches tested SHA2563a9a8aed5a893df2d64fe5866cbb35d4fa2cafade27786ba7cb7a63dee66817d. IPA17655449B SHA2561f9ca7b9d294a2a8b723706f8714ca2a5898ec256e8976c3380d0c1d9322800a. Published only this new installer in the existing static-download service; preserve old installers/app data, no Caddy/config/service restart. Public download verification recorded after actual completion.

- Public delivery verification completed: HTTP206 bytes0-31/17655449 and complete17655449B HTTPS download both match SHA2561f9ca7b9d294a2a8b723706f8714ca2a5898ec256e8976c3380d0c1d9322800a. Only new0.6.83 installer published. Physical continuous iPad viewing remains the final acceptance step; no blanket network-root-cause or field-resolution claim.

## 2026-11-09 · USB deletion baseline correction

User correctly identified installed iPad0.6.83. Initial0.6.59 baseline was wrong because only apple-build.yml runs were queried. That candidate branch4efc86c is superseded and run42624786296 cancelled; it must not be installed. Verified0.6.83 sourcebeb719c1a81e339bc6cea07ff62dc74b727ef258, successful device/native build42016927669, artifact13410148385; current baselinec797f3f91d045da0e06aece2764fb61fdc60ef31 only appends verification records.

New branchfeat/ipad-router-usb-delete-0683 preserves0.6.83 app/tests/resources, adds only USB native management/browser actions/3 network-result tests and candidate0.6.84/build144. Preserve TMDB toolbar action during patch merge. Private backend13985cc adds opt-in deletion;52 synthetic Python tests pass. New isolated CI inherits the delivered ARM workflow and native regression selection, adding USB management/catalog cases. No production USB changes, deployment or installation. Router current write mode is unknown: connected movie capability tool failed MCP_CONNECTION_FAILED; old read-only documentation is historical, not a current measurement. Rollback: keep0.6.83 installer and original branches; deleteEnabled remains disabled by default.

## 2026-11-09 · Native compile correction

Actions42625161921 failed in device compilation: RouterUSBManagement.swift45 assigned to the shadowing let parameter session. Corrected initializer to self.session; native tests were skipped in that failed run and remain unverified pending new CI. Router capabilities still fail MCP_CONNECTION_FAILED. No live changes.

## 2026-11-09 · Hosted ARM runner capacity failure
- Run42626638985 did not start any job step. GitHub annotation: "The job was not acquired by Runner of type hosted even after multiple attempts" and ARM capacity notices. This is runner allocation failure, not compilation/test evidence.
- Move isolated USB deletion workflow to macos-15-intel, retaining the same Xcode26 selection, generic iOS device ARM64 build, all native regressions and fullscreen UI checks. No app/test assertion changes; public app source remains25d7091. Prior baseline notes record simulator subtitle timing differences on Intel; retain existing assertions and report any actual failure.
- Router deletion production status supersedes earlier pending notes: backend7f7c14b preserves existing ext4 support, validates physical filesystemUuid, permits external GL automount alias while refusing nested mounts;53 local Python tests pass, actual USB synthetic HTTP delete passed, admin only restarted, production session reports deleteAvailable true and existing password settings preserved. No pre-existing user movies deleted. iPad installer still pending native verification.

## 2026-11-12 · MovieMind requested iPad package
- User follow-up asks for the iPad version after MovieMind source/validation delivery. Isolated build/moviemind-ipad-085-20261112 keeps all iOS application/test/project files identical to successful UI source7410258 and native/device source88cc5da; no playback/source/sync behavior changes.
- Dispatch-only workflow reuses standard free public macos-15-intel/Xcode26 for the Release device build, checks0.6.85/145/iOS-device ARM64 and bundled notices, then encrypts the unsigned IPA to a public age recipient before artifact upload. The private decryption identity stays outside repositories and CI; no Apple signing credentials or plaintext installer are uploaded.
- Workflow YAML/shell syntax, ciphertext-only artifact allowlist and a real age encrypt/decrypt roundtrip passed locally. Earlier actual evidence remains101 native PASS and2 UI PASS. The packaging run is pending at this checkpoint. Signing/installation/physical paired playback and production deployment remain unverified; no main merge or public plaintext installer publication.

## 2026-11-12 · MovieMind iPad package success
- Run43186208149 at source5d1a988 SUCCESS: Release device build, original unsigned IPA packager,0.6.85/145/dev.together.poc.asrtest/iOS-device ARM64 and notices validation. Entire iOS treee34b2779 is unchanged from validated7410258 and the private source branch;101 native/2 UI earlier passes remain separate actual evidence.
- IPA17836938B SHA25676c75019a788688b924c9efd1b9119d5b11818d36725c88561a43abad973ee8a. Only age ciphertext and non-secret provenance were uploaded. Requester privately downloaded/authenticated-decrypted and verified digest/CRC/Info.plist/Mach-O/notices, then deleted this run's temporary encrypted artifact13929042180. Private identity/signing credentials never entered this repo or CI.
- Unsigned local candidate returned; signing/installation/physical paired/HDR acceptance remain unverified. No plaintext installer publication, paid runner, main merge or production service/database/network update.

## 2026-11-12 · MovieMind0.6.86 native login regression and package
- The same-device web login works while the old native form shows a generic failure. Client-only candidate normalizes origin input, separates interactive login from short background timeouts, reports sanitized HTTP/network/Keychain errors and preserves failed input/old session/drafts.
- Explicit temporary-login option is offered after secure-storage failure; token remains in the current actor, with mode and receipt scope preventing stale credential reuse after relaunch. No cookies retained in native transport. Ten native policy/transport regressions added; original101 native and2 UI assertions retained.
- Whitelisted iOS source/project/tests only, no private config/history/accounts/keys. Standard free Apple package/native/UI jobs; only age ciphertext uploaded, private key remains outside repos/CI. All jobs must pass before private candidate delivery. Current local policy2 PASS/parse PASS; Apple results pending, no physical resolution claim, server/network change or public plaintext installer.
