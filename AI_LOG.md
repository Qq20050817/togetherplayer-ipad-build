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

## 2026-11-04 · User correction supersedes automatic wait
- Latest user instruction: no automatic pause for ordinary drift or peer buffering; pause belongs to users; explicit SEEK goes to both. Historical smart-pause text was supplied as reference, subsequently superseded by this clarification. Remove the erroneous >10s automatic local pause.
- Candidate uses lag>5000ms continuously for5000ms, resets on brief recovery, invalid/gapped samples or buffering; normal speed within3000ms. Sustained duration awaits user preference; candidate default5s. Leading device keeps normal requested speed, no automatic backward SEEK/pause.
- Preserve verified manual SEEK confirmation, live clock, fullscreen native slider and Android local-first routing/reconnect/permission/identity/subtitle/audio behavior. Native regression/build pending for this candidate.

## 2026-11-04 · User confirms ten-second persistence
- Supersedes candidate5s duration: lag must be strictly>5000ms continuously for at least10000ms before local rate catch-up starts. A return to<=5000ms before activation clears the timer; active catch-up returns to1x within3000ms. No automatic pause. Manual SEEK remains immediate.
- Earlier5s-duration CI candidates are superseded, not final deliverables. Update native/standalone boundary and interruption tests; rerun required.

## 2026-11-04 · Ordinary room SEEK confirmation gap
- Source audit found Media3Adapter.seekTo called Player directly, so normal server-driven explicit SEEK bypassed the MainActivity native-position confirmation/15s failure tracker used by instant control. Route adapter seeks through seekManually; default adapter behavior remains available to independent users/tests.
- Add real HTTP paused-room small SEEK confirmation plus a simulated ignored native request deadline: require failure feedback and actual clock/position rather than a fabricated pending target. New native test/build required; not yet marked passed.

## 2026-11-04 · Verified final ten-second sustained catch-up delivery
- Application64aba059ab087c562f0718628ab28d0d6208c3c3; version0.6.60.10/130; Actions41812565306 SUCCESS. 142 JVM tests +40 native emulator tests;0 failures/errors/ignored/skips. New real HTTP ordinary SEEK confirmation/ignored-seek deadline, deleted-local-file, no duplicate HTTP after local/reconnect/renewed URL/retry, explicit unbind/grant checks pass.
- Archive digest verified against GitHub artifact metadata and actual downloaded bytes. Installable292693449 bytes SHA2562753e73c61eed20aef104e78a51be0d74274bcad3b58259ac348192be40b389e; extracted digest matches build checksum; manifest/plist confirms version/build and isolated application identitydev.together.poc.fluency.
- Final rule: lag strictly>5000ms continuously for at least10000ms before local acceleration; return<=5000ms before activation resets qualification; invalid/missing samples or buffering do not count. Active correction ends within3000ms. No automatic pause, backward SEEK or leading-device slowdown. Explicit user SEEK bypasses all timing/threshold gates.
- Preserve Android local priority, SAF grants, content/cut identity, real-position/subtitle/audio continuity and reconnect safeguards. Ordinary Android room SEEK now uses native confirmation/deadline tracking. Native clock and iPad native slider commit/cancel fixes retained and regressed.
- Server27a621c4 deployed with consistent DB/previous executable backup;84 server tests, race/vet and local/public two-connection protocol checks pass for peer buffer/fault/disconnect continuity and explicit pause/SEEK. Old automatic-wait PR34/35 closed as superseded; earlier5s-duration CI candidates not delivered as final.
- Physical pair, hardware-format combinations and long video runs remain unverified: Windows/Muse control connections return errors. No client install, user-data deletion or main merge. IPA requires user signing; Android CI debug signing is not promised compatible with an existing preview, never automatically uninstall. Logs committed on feature branches; main-only AI Journal ingestion not claimed.

## 2026-11-04 · Xiaomi Pad7 direct-file delivery
- User identifies Xiaomi Pad7. Baseline5f4b4bb, verified app64aba05/0.6.60.10 (142 JVM+40 native). Original universal APK292693449B exceeds connector100MiB transfer cap.
- Packaging-only candidate0.6.60.11/131: ARM64 ABI filter plus compressed native libraries/extraction; retain all application source, offline voice model, local priority, Seek confirmation and sustained>5s/10s catch-up rules.
- Independent delivery branch; no main merge or app uninstall/data reset. Run JVM/native suite with compressed libraries, then build ARM64 delivery and require <100MiB, onlyarm64 libraries, compressed JNI, intact voice model SHA. Physical Xiaomi Pad7 install/playback remains unverified. Candidate build pending.

## 2026-11-04 · Xiaomi Pad7 compact APK verified delivery
- App/source78ea8306d6a723bc221ae15262423cbe0b9b8476;0.6.60.11/131; Actions41817230504 SUCCESS.142 JVM tests +40 native emulator tests,0 failures/errors/ignored/skips; native suite ran with compressed JNI/extraction, followed by ARM64 assembly.
- Artifact13316215327 archiveSHA256af092ddfa1c68115f4065df0a47b7c0653e7b44b980f1f12977738dbe596cecf independently verified. Raw APK78557417B (78.6MB), SHA2564eb4e200fc0fec63b575ff144c4e558f65ef995787c541ece08dbe1ea3aa269b; actual public full-file download matches. Manifest0.6.60.11/131/dev.together.poc.fluency, extractNativeLibs=true; six ARM64 JNI libraries only, all compressed, every uncompressed library byte hash matches verified0.6.60.10. Offline voice model SHA matches original; no functionality removed.
- Official Google apksig8.6.1 independent verification passes. New signerSHA25640815d7c656f8c49fcfdc61f215822f904327c06cf517b180b5f80d5873301ec differs from original0.6.60.10 signer6c62ddbfbd096998dec4317cb722a208170f109949dfdae7020ae60f26f5d656. Do not promise overwrite upgrade or uninstall an existing preview; preserve data if signature conflict is reported.
- User cannot open Google links; direct HTTPS original APK/IPA published via an existing server static-download route. No Google login, ZIP extraction, Caddy configuration change or service restart required. Server-side range and independent full-file retrieval verified; user-side China access confirmation still pending. No physical Xiaomi Pad7 install/format/long playback acceptance claimed. Main unchanged.

## 2026-11-04 · Installed Android USB decoder investigation, candidate0.6.60.12
- User confirms installed Android0.6.60.11 and iOS0.6.80. Verified Android baseline78ea8306d6a723bc221ae15262423cbe0b9b8476, delivery HEAD1793647, Actions41817230504 success142 JVM+40 native; isolated fix/android-usb-decoding-06012-20261104. Preserve current SyncCore, ordinary SEEK callback, local-first controls, compact ARM64/JNI packaging, and offline voice.
- Reuse only bounded audio fallback/diagnostic logic from prior3e30ee5 candidate, not its older sync logic/version. Distinguish decoder errors from HTTP errors; capture actual audio decoder instead of attributing audio errors to the video decoder. DTS/TrueHD audio runtime failure may select one supported same-language AC3/EAC3/AAC track, keep true position/subtitles, defer autoplay to room. Video failure remains separate, exact device cause unknown.
- Prior41847252992 native failures were reflective loadMedia signature mismatches. Update all invocations for nullable preferredAudio while retaining assertions; add actual HTTP AAC fixture with English metadata and native fallback/retry-bound/pause/position/subtitle/source test. Metadata-only fixture derived from existing synthetic test media, no user movie copied.
- iOS hotspot works; original home OpenWrt Wi-Fi uses automatic DNS, proxy off, no iPad VPN. Singapore health200/trusted TLS1.2/1.3 pass. Windows IP-pinned200 probes run with its VPN adapter present; not proof of iPad direct path. Router maintenance startup timed out before a router shell was confirmed. No router/server config or media changes; Wi-Fi cause remains open.
- Native build/regressions pending; source diff check passes. No install, merge, production deployment or physical playback claim. Rollback: retain installed0.6.60.11 and candidate baseline; do not uninstall for CI signing differences.

- Review before native CI completion: clear the failed explicit audio override and prefer the chosen compatible MIME before prepare; pending exact track override still applies after discovery. This prevents immediately reopening the same failed DTS track. Rerun required; no successful candidate verification inferred.

- Independent Singapore public endpoint probe completed: POST create/join201; authenticated TLS1.2 andTLS1.3 WebSocket WELCOME; same-credential reconnect WELCOME; synthetic room closed. This verifies server protocol capability, not the failing iPad Wi-Fi route.

## 2026-11-04 · Android candidate native verification and signing boundary
- Exact applicationccdeec1ac043fba72f74a35d39474f0d3ac38d3d; Actions41853120352 SUCCESS.145 JVM tests and41 native tests,0 failures/errors/skips. Includes actual HTTP compatible-audio recovery at native position with same room/source/subtitle, no autoplay and bounded retry; existing local/SEEK/decoder/voice tests retained.
- Artifact13336498921 ZIP SHA25627b6d276b74f079b6932d18fe8127209f00db271406abe2941f7afe4950182b3 verified from official download, ZIP integrity passes, APK78561613B SHA2566c31758eaa0a1db6d0561428d4b01c5bc3ec3b21941684d578f5dd8335fe6c4c. ARM64-only compressed JNI and voice-model hash verified.
- APK v2 certificate SHA2564c27b494e7aa76fe32475d53ff753f8e3070f254ce4a5d8cdbfaf907dfe5f1ce differs from installed0.6.60.11 signer40815d7c...; do not offer uninstall/overwrite as a prerequisite. New packaging-only workflow preserves verified application source, changes runtime suffix to.decoder12 and display label toTogether解码测试, verifies coexistence with exact0.6.60.11 in an emulator, then emits compact ARM64 package. No source logic or runtime data migration. Parallel package verification pending.
- User supplied audio menu: English Dolby Digital5.1 track1 and French Dolby Digital5.1 track2 plus English DTS tracks3/4. Asked user to select English track1 and retry; result pending. This metadata/menu does not yet establish the failed renderer.

- Packaging smoke correction before execution: exact0.6.60.11 is ARM64-only and cannot be installed normally on an x86 emulator. Use verified universal0.6.60.10 artifact13313177972 (APK2753e73c...) as the coexistence fixture with the same dev.together.poc.fluency identity.0.6.60.11 shares that identity and application logic; physical ARM64 coexistence with installed0.6.60.11 remains unverified. No prior ARM64 install success is claimed.

- Parallel packaging runs41856053422/41856214146 failed before compilation: default shallow checkout omitted the verifiedccdeec1 source object used by the equivalence check. Fetch full repository history for that check; retain strict source comparison. No application change or successful parallel install claim from those runs.

## 2026-11-04 · User rejects audio-only explanation; HTTP HEVC recovery
- User explicitly selected the English Dolby Digital track and reports no picture or sound. This does not establish the failed renderer, but audio switching alone did not resolve the fault. The prior145+41 passing candidate is diagnostic/audio-only and is not the final video-fix delivery.
- Concrete source gap: independent software HEVC decoder accepts only content/file sources; router USB is played over HTTP, so the same independent path is unavailable after native decoder exhaustion. Add explicit ordinary-HTTP opt-in only after an actual HEVC runtime failure and exhausted supported OS alternatives. Account-header sources and URI credentials are excluded; retain exact URI and native playhead, external subtitles and room intent. No transcode/upload or media mutation.
- Preserve standard default local-only activation. Network input uses normal TogetherPlayer UA rather than an unrelated Baidu UA; independent exceptions use safe class-only text. Actual independent READY now clears sourceFault. Add pure source-policy tests and real HTTP HEVC Main10 frame/position/subtitle/pause/switch-back native regression. Existing local Main10 test remains. Full JVM/native rerun required; physical Pad74K performance and original-file acceptance remain unknown.
- Parallel packaging built from the earlier audio-only source is superseded; final parallel packaging must compare with the newly verified application source. Existing installed0.6.60.11 stays intact.

- Final parallel package source checkpoint now 9354947e379eb617d69d23b14eeb4b32078d6866 (HTTP HEVC recovery), replacing the audio-onlyccdeec1 packaging comparison. Both full native application CI and coexistence packaging must pass against this code before delivery.

## 2026-11-04 · New HTTP test fixture thread and parallel label correction
- Full148 JVM compilation passed;42 native run41857216782 had one failure before decoder activation: new test first resolved MockWebServer.url on the main thread, raising NetworkOnMainThreadException. Downloaded native XML confirms stack getCanonicalHostName -> FixtureHttpServer.getUrl -> test line41. Resolve the fixture URL on the instrumentation thread, retaining frame/real-position/subtitle/pause/source-fault assertions; no production StrictMode relaxation. Existing41 native cases passed. Add an early scoped HTTP Main10 run before the full suite for clear fail-fast evidence.
- Final HTTP-source parallel package41857465793 passed build/coexistence/launch, but separate artifact inspection found the debug manifest overrides the intended launcher label with流畅预览. Override both main/debug labels only in the packaging job and require the final aapt label. Private staged artifact is not released. Native app source remains9354947.

- Fast scoped run41859361425 compiled but did not produce a displayed HTTP Main10 frame within45s; do not release that candidate. Its synthetic source is only2s long, leaving0.5s after requested1.5s recovery, unlike the full-film case. Keep every frame/position/pause assertion, extend only the synthetic fixture to8s using bitstream-copy repetition (same HEVC Main10 codec/4K frames) and add numeric renderer/request/view diagnostics to failures. This is fixture investigation, not a passed playback claim; rerun required.

## 2026-11-04 · Final Android HTTP recovery native and package evidence
- App source9354947e379eb617d69d23b14eeb4b32078d6866; final test checkpoint387cee045205dfc300c300b83768f680d7b1ae07. Run41861295638 finished build/test/package/upload steps successfully; independent HTML/XML extraction confirms148 JVM tests0 failures/ignored and42 native tests0 failures/errors/skips. Scoped HTTP Main10 test also passed before the full42. Native workflow run metadata still reports in_progress after all steps completed; do not invent a final workflow conclusion.
- Earlier9354947 test failure was main-thread fixture DNS; cb62178 failure used a2s fixture with1.5s seek and no displayed frame.8s synthetic bitstream-copy fixture passes actual frame/position/pause/subtitle/source-fault assertions. Production app code stayed9354947 throughout these test-only corrections.
- Final parallel build cb62178a0623dd8489d751fc584f2800028f5220 /41859361593 SUCCESS, artifact13340160028; archiveSHA256aff2e8d125df781ca7d75bf645eaeed5a3f1150fd970b752d41a64dbad3ae436 independently verified. APK78562705B SHA2561e94c08cd4f98bca1a5f8435fe06e051c2084889992276bc826ee857319a8c9f; manifest0.6.60.12/build132/dev.together.poc.decoder12, actual launcher labelTogether解码测试, compressed ARM64 JNI and offline model checksum verified. Real coexistence/launch with verified universal0.6.60.10 .fluency identity passed; installed ARM640.6.60.11 field coexistence not separately observed.
- Copied only this verified public APK to existing static-download directory, preserving older installers. No Caddy configuration, server process, router settings or original media changed. Public HTTP Range/full-download verification recorded separately after actual completion. No physical original-film,4K sustained/HDR/Atmos quality or paired-device acceptance claim. Keep old app/data as rollback; remove only parallel test app if reverting.
- iOS candidate cfe66a1 app / d9b870c Intel workflow on separate PR39 remains uncompiled: ARM pool acquisition failures and first Intel acquisition failure occurred before any build steps. One Intel failed-job rerun is queued. No new IPA delivered; user confirms hotspot succeeds while home Wi-Fi app fails despite Safari success. Main branches unmerged.

- Public delivery verification completed: HTTP206 bytes0-31/78562705 and an independent complete public HTTPS download78562705B both match APK SHA2561e94c08cd4f98bca1a5f8435fe06e051c2084889992276bc826ee857319a8c9f. Link supplied to user for original-film test; physical result pending. Only the new standalone installer was published; older installables/configuration/services remain intact.

## 2026-11-05 Asia/Shanghai · Physical0.6.60.12 feedback and output candidate
- User confirms audio restored but progressive gray/block corruption around00:34, including without a floating window. Only iPad room transport disconnects; Android room disconnect was not reported. Old iPad versions also fail on home Wi-Fi while hotspot is usable, so a new-app-only regression is not established.
- Read-only server diagnostics identify actual video/hevc hvc1.2.4.L150.90 3840x1600 c2.android.hevc.decoder failure followed by independent HTTP fallback. Bounded desktop decoding of the same router source at10/34/60s succeeds with no reported decode/reference errors and clean frames. This narrows the client decode/output path; it does not certify the entire film or establish a specific low-level cause. No original media or router/server config changed; no private frames, URLs, contacts or raw production logs added to this repository.
- Verified baseline62bc69a / application9354947 / native checkpoint387cee0 / delivered parallelcb62178. Isolated fix/android-main10-texture-output-0613-20261105, candidate0.6.60.13/build133. Preserve working audio, same-source/position/pause handling and synchronization thresholds. Change both initial/rebound independent output toTextureView and disable avcodec direct rendering so software reference frames do not share recycled display buffers. This is an output compatibility candidate, not a proven root cause or field fix.
- New48s synthetic Main10 HTTP fixture repeats only existing test bitstream. Native test checks actual RGB color stripes repeatedly beyond30s, real advancing clock, fullscreen detach/reattach and pause. Full native build/regression and user-device validation pending; older8s frame-only success did not cover this symptom.
- The10s frozen-playhead paired PAUSE/system assistant feature remains separate and undeployed. Existing catch-up remains lag>5s sustained>=10s, ending within3s. The live backend executable hash remains27a621c4; no sync-policy or server deployment in this phase.

## 2026-11-05 · Android-only continuation
- User reports iOS resolved and requests only the Android build. Stop iOS investigation and builds.
- 0.6.60.13 run41871520730 compiled and passed unit tests but failed its new first TextureView color read immediately after decoder READY. Do not call native validation passed. Start playback before the first timed color sample (2.5s), retaining repeated color, duration and reparent assertions, and report actual RGB on failure. Full regression pending.
- Build parallel `.decoder13` / Together 画面测试 to preserve both installed apps and their data; complete app source is checked against a7aba03. No sync change.

- Run41993207241 installed both identities and launched successfully, but its UI XML shows the emulator Quickstep ANR overlay, not an app crash. Add a preflight that dismisses only this known launcher dialog. Run41993207204 color test returned transparent TextureView bitmap; switch to actual composed-screen color checks off the main thread, keeping the same color majority/long run/fullscreen assertions and preserving a synthetic failure screenshot. Both native checks require rerun; no physical fix claim.

- Reruns41994236386/41994236389 were blocked before actual playback by preflight parsing a missing accessibility root after stopping the launcher. This is a test harness defect, not a new app result. Allow the normal pre-launch no-window case, then repeat the specific launcher-dialog check after package launch; app UI and all playback assertions remain required.

## 2026-11-05 · Output candidate correction
- d29235f package41995109164 built and coinstalled successfully, but native41995108894 fails actual composed color after fullscreen reparent. Its synthetic screenshot shows black video at13s while controls remain visible. This is a real TextureView lifecycle regression, not a passing candidate. Do not deliver that APK.
- Revert only TextureView output to the previously verified SurfaceView path; retain decoder-owned Main10 reference pictures via avcodec-dr=0. Keep the same long actual-screen color/fullscreen/clock assertions. Original-film gray corruption remains physically unverified. No audio/sync/iOS app changes.
- User confirms the intermittent room disconnect/P2P fallback stutter on iPad only; Android occurrence unknown. Earlier create/join iOS failure resolved per user. Keep these iPad symptoms separate and open while completing requested Android build.

- SurfaceView rerun41996258264 reproduces the same black fullscreen output at13s; prior wording attributing it solely to TextureView is superseded. New color checks reveal a shared reattachment gap. LibVLC VideoHelper.detachViews explicitly disables the video track; its internal surface-created handler can skip reenabling while old vout count remains nonzero. Explicitly reenable video after new surfaces are ready and update geometry, preserving media/position/audio/pause intent; add safe track/attachment diagnostics. Native validation pending. Packaging41996258118 passed but is not released while this assertion fails.
