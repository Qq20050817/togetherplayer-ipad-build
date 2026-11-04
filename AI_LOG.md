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

## 2026-11-04 · Android USB/local-first baseline

- Branch fix/android-local-first-usb-stability-20261104 at 1553ef43b682a82d5985a3a3acc04ef1f837ec21; application directory exactly matches verified 6363aad / 0.6.60.7 (Actions41734109853). Clean before phase edits.
- Read-only GL-MT3000 test: existing ~22GB MKV and ~97MB MP4 HEAD lengths match disk; 206 and Content-Range checked at head, around 2GiB/4GiB boundaries and tail; returned bytes match direct file reads. Beyond EOF correctly returns416; interrupted full response then ranged reconnect passed. No >4GB MP4 was available, no physical Android external-network test yet. Zero original-file or service changes.
- Media server inspected SHA256906bc1c8416bb43f0bda2d5cb133272a3d286a0d4dc53c3b5704fb87d3fccbe0. Python integer range math shows no truncation. Production configuration/credentials and media names are excluded from logs.
- Client findings: ordinary HTTP local picker skips fingerprint validation; switch defaults can clear subtitles; source reload uses old canonical snapshot instead of actual playhead; all HTTP errors beyond a small whitelist collapse to generic decode/source labels.
- Planned minimal changes: central per-device local priority guard; bounded HTTP range identity validation; explicit confirmation plus duration gate for differing/unavailable byte identity; preserve selection/real position; classify HTTP failures and retain bounded retries. Server changes only if a specific failing protocol check is reproduced.
- Rollback: previous isolated candidate remains available. Production services, media and main are untouched.

## 2026-11-04 · Local-first/USB candidate edits

- Local source policy is enforced centrally at every load; renewed HTTP room URLs cannot replace a valid same-movie binding. Explicit unbind still enables HTTP. Changed sources stop and clear old player input before preparation; existing external subtitles and preferred audio language are retained for verified same-film switches. Actual playhead is used at switch/recovery time.
- Normal HTTP selections now compare three bounded 64KiB byte samples plus length to the local fingerprint before binding. Unavailable/different byte identity requires the existing explicit same-cut confirmation and duration gate; no whole-file upload. In-flight identity reads can be canceled. Confirmed-variant duration requirements survive reconnect persistence.
- Error classification separates HTTP auth/unavailable/range/server/throttling, timeout/connection, incomplete data, unexpected content, local access and container errors. Existing two-attempt backoff/dedup is preserved; EOF-like recoverable failures can use it. Private rotating, asynchronous, bounded metadata diagnostics retain no URLs, paths, token or media names.
- HTTP measured speed is smoothed; repeated-stall reserve considers known stream bitrate. Catchup needs advancing frames and at least 3s buffered reserve, avoiding acceleration into an empty buffer. Existing hardware/FFmpeg audio and bounded HEVC fallback paths are retained.
- Added: long-offset/range validation, bounded network identity, source routing, redaction and error classification unit tests; real HTTP/local switch and zero-reload native test; existing SAF UI tests now use matching HTTP fixtures while preserving picker/frame/seek assertions. New isolated CI 0.6.60.8/128 prepared.
- Not yet compiled or executed for this candidate; field tests and unsupported-format combinations are not marked passed. Production router/services and original media untouched.

- Audio selection continuity: capture selected format identity/language/label/codec/channels; reapply a matching supported group once after source preparation, or explicitly ask the user to check audio if no exact match exists. Added native tests for explicit invalid-grant fallback and deduplicated transient recovery retaining real position and subtitle. Native field/hardware combinations remain unverified until CI/device testing.

- CI preparation run41738428661 remained in setup-gradle for more than five minutes before compilation. Disabled shared Gradle cache restoration and bounded that setup step to five minutes; same application source, same tests. No test result is inferred from setup delay.
- External IPv6 read test after 4GiB returned206 and exact64KiB matched disk in ~1.3s. Remote container probe recognized HEVC Main10 3840x1600 with DTS-HD MA/DTS/AC3 and PGS tracks; this is metadata/transport evidence, not a physical Android decode or full playback claim.

## Reconnect picker regression follow-up
- Run41739201207: full JVM checks and APK compilation passed; 35/36 native tests passed. Existing picker-after-reconnect test still used an unverifiable example.org URL, correctly triggering the new identity confirmation gate. Replace only its HTTP fixture with identical bounded-Range sample bytes; retain Activity recreation, disconnected picker return, WELCOME and final selected-URI assertions. No production behavior or identity gate weakened. Rerun required.

## Optional source-fault protocol candidate
- Real Media3 or compatibility errors immediately report sourceFault=true, retaining it through same-source retries until actual READY. Source replacement clears old transient fault. Periodic status includes optional boolean; old server/clients remain compatible. Native retry regression now verifies fault retention and READY clearing.
- Matching private server candidate isolates active HTTP/local source faults from automatic wait, while retaining ordinary buffering, disconnect, manual-pause and Baidu identity gates. No backend deployment performed. This protocol requires the separately tested server update to affect automatic wait. Android candidate rerun pending.

## HTTP error-page misclassification follow-up
- Review found default HTTP source accepted successful-status HTML/JSON error pages, allowing extractor failure to masquerade as unsupported container. Add shared HTTP factory for normal and Baidu paths rejecting only explicit HTML/XHTML/JSON error MIME types before extraction; retain absent MIME, generic binary, HLS, text/VTT and local sources.
- Added real MockWebServer/Media3 data-source tests: HTML becomes UNEXPECTED_CONTENT without app retry, missing/binary MIME still reads bytes. Native/unit checks pending next candidate; no production/router modification. Media3 factory API checked against official androidx/media source.

## Retry budget cannot be replenished by room pause
- Review found the existing shared playerRebuildCount resets on a paused room tick, potentially granting unlimited automatic HTTP retries. Introduce a separate two-attempt consecutive HTTP budget, retain scheduled-error dedup before exhaustion, preserve budget across same-source reload/pause, reset only on explicit retry/source replacement or30s actual advancing playback. Keep existing other decoder/recovery counters and wait intent.
- Added policy regressions for long paused/unready intervals, interrupted vs continuous healthy playback, and explicit reset. Full Android rerun required; not yet marked passed.

## Candidate consolidation
- Current application9a36b3f7c43e487d9c527daa81442b5dc21c442d, Android0.6.60.8/128, full run41742801175. Earlier c863015 and0999f58 runs superseded/cancelled after additional code findings; their partial build success does not verify this application. Record final counts only after current completion. All changes remain on independent branch/PR32, unmerged/undeployed.

## Android0.6.60.8 verified candidate checkpoint
- App9a36b3f7c43e487d9c527daa81442b5dc21c442d; run41742801175 SUCCESS. HTML unit summary137 tests,0 failures/ignored; native XML38 tests,0 failures/skips. Includes matching HTTP/local binding, SAF MP4/MKV decode+Seek, reconnect picker, forcedHTTP prevention, explicit invalid-grant fallback, real-position/subtitle retry retention, sourceFault READY clear and actual HTTP error-page/data-source checks. APK compilation and existing decoder/voice/UI scripts passed.
- Archive13282653792 SHA256265e67deac8f86808eacab323a7588c99730d219a54c39283683f7156ca602cf verified. APK292,693,449 bytes SHA256abd3076925d0a379fc244e2282f551727e5b4b372447f1918d6a080c03ab8ff5. Version0.6.60.8/128 retains .fluency test suffix; ephemeral CI signer may require separate handling from an installed preview. Never uninstall user app automatically.
- Independent PR32; no main merge/deployment/install. Physical Android HEVC/HDR/DTS/TrueHD combinations, long playback, large MP4 field test and actual two-device mobile network tests remain open. Private server9bd65d45 protocol counterpart not deployed, so healthy-peer source-fault isolation is not yet active in production. Greater-than10s automatic pause-intent distinction is not implemented in this phase.
- Recovery: prior independently verified delivery remains available; source rollback9a36b3f or initial6363aad as appropriate, retaining local grants/data. Main-only AI Journal has not synced this feature branch; GitHub logs are committed, no false main ingestion.

## 2026-11-04 · Leading-device wait candidate
- Baseline 31d5c468c67420fc150e17de45415f0d36963be2; independent leading-wait branch. Candidate only, no deployment or installation.
- Local ahead >10000ms pauses only this device; resume at <=1000ms ahead. Check latch before native-running gate; preserve manual SEEK, room PAUSE, question gates, offsets and source errors.
- Exclude intentional wait from stall recovery. Optional syncWaiting status is diagnostic; do not report it as buffering or a shared PAUSE.
- Regression/build pending; hardware pair and long playback unverified.

## 2026-11-04 · Android leading-wait verified delivery
- Applicatione2e2dad886af803134fa76820460e263b47acffe, candidate0.6.60.9/129. Actions41807034832 SUCCESS:141 JVM tests0 failures/ignored;38 emulator tests0 failures/errors/skips. New waiting boundary/resume/override/offset/reset/buffering tests passed with existing source-routing, decoder and Seek coverage.
- Artifact13310518213 archive SHA256cab3bacd35078150519ad3937580e89b0ea72ad6662c6b3d330546fd60b347fa verified against downloaded bytes. APK292693449 bytes SHA256f6aec035412c856a197448242b5b5dc74773a0ff78245ed50144f027fc8b0164; extracted hash matches build checksum. Filename version0.6.60.9 despite inherited artifact group name0608.
- Intentional wait compares local position (with timeline offset) against canonical room time. It is local only, does not issue shared PAUSE, resumes within1000ms, and is not stall recovery. Existing server ordinary-buffer wait (~2s) remains a distinct policy; this change does not claim peer-position-based waiting.
- Production source-fault counterpart was separately authorized, backed up, deployed and verified via local/public two-connection protocol checks. Existing ordinary buffering and manual pause behavior preserved. No client install or branch merge. Physical Android/iPad pair, hardware combinations and long playback remain unverified; original candidates remain rollback. Feature-branch logs are committed; main-only AI Journal ingestion is not claimed.
