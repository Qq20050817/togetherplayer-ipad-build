# AI Issues

每条问题需记录：ID、时间、影响范围与版本、复现步骤、可核实的报错、根因（未知则写未知）、修复提交、回归验证、当前状态。

初始化时尚未逐项验证历史故障。过去聊天或文档中的问题应按 GitHub 代码、测试和实际运行证据重新核对，不能自动标为「已解决」。

## TP-SEEK-CLOCK-20261104

- Status: candidate edits, native CI pending.
- Evidence: both engines hard-seek at >1500ms, conflicting with tolerance; iPad native completion discards finished; canceled/accessibility drag can leave preview latched; Android compatibility getter returns requested target for 3s before native acknowledgement; UI refresh shares network/sync runnable with no guaranteed reschedule.
- Additional confirmed queue issue: coalescing all INSTANT_CONTROL operations loses a queued PAUSE when a later SEEK arrives. Changed to coalesce by command category.
- Verification: new native tests and baseline-replay CI prepared. No claim that every reported intermittent device symptom has been reproduced. Physical dual-device HTTP/Range/cloud playback, background/fullscreen long runs remain pending.

- CI-discovered regression: unready explicit-seek gate initially deferred PAUSE. Original Android pause-while-unready test caught it (119/120). Both platforms now apply PAUSE before checking readiness; rerun pending.

## TP-ANDROID-USB-HTTP-20261104 · queued next phase

- Priority: high. User requests work after the current Seek / clock candidate is verified. Task tsk_823ab96ad4c494ba. No compatibility fix or router verification is claimed yet.
- Protocol: inspect GL-MT3000 service; verify >4GB MKV/MP4 offsets, 206, Content-Range, full length, EOF boundaries, seeking, interrupted reads and reconnect. Avoid integer truncation.
- Diagnostics: distinguish timeouts, connection interruption, HTTP status, unexpected response body, incomplete bytes and inaccessible file. Record only redacted error/status, decoder capability, encoding, buffer changes and recovery outcome.
- Recovery: bounded retries, backoff, deduplication and cancellation; preserve actual playhead, subtitles, audio selection, source binding and room state.
- Decoder: test MKV/MP4 + H.264/HEVC/HDR + DTS/TrueHD/AAC combinations. Prefer hardware, then existing bounded compatibility fallback. Unsupported combinations need precise reasons; assess remux/audio handling; optional transcoding only. Never modify originals automatically.
- Buffering: evaluate throughput, bitrate, reserve and stall history; prevent policy-driven repeated stalls.
- Synchronization: one source read failure must not pause the healthy peer incorrectly; preserve 3000ms tolerance, catch-up and agreed intentional pause/wait semantics. Backend deployment identity must be verified before backend changes.
- Acceptance: first play, long run, rapid/distant seek, network loss/recovery, dual-device sync across sizes/codecs/audio. Keep all historical features and publish actual evidence/limitations.

## TP-ANDROID-LOCAL-FIRST-20261104 · queued next phase

- User requested alongside the queued USB HTTP compatibility work, after current Seek/clock validation. Preserve historical local-source reconnect protections.
- Per-device source policy: a valid, explicitly selected, identity-matched local file takes priority immediately; stop old HTTP video reads/preload after switching. Without a valid local binding, room USB HTTP remains available.
- Room updates, synchronization and reconnect must retain the valid local binding. Transient local buffer/decoder failures recover locally without silently selecting HTTP.
- Missing file / expired SAF access / user cancellation: clear explanation, reselect action and safe explicit USB fallback; do not permanently trap the user or silently select a mismatched source.
- Match necessary file information/content identity/duration and cut; reject unrelated movies or incompatible edits. Use Android system picker and persistent read permission, never whole-film server upload.
- Switching affects only this device, retains actual playhead/subtitle/audio where possible, and preserves two-device synchronization, 3000ms tolerance, catchup, intentional pause/wait and progress controls. Explain incompatible selections.
- Required regressions: local priority; USB fallback; reconnect and jitter; temporarily buffering local source; missing file/expired permission; explicit switch/unbind; peer unaffected; same-film different-source synchronization; no duplicate HTTP reads.
- Status: requirements recorded; no new implementation or passing test claim.

- TP-SEEK-CLOCK-20261104 latest status: candidate automatic validation passed on both platforms at the exact commits recorded in AI_LOG.md. Initial pause-while-unready regression resolved (120/120 JVM); iPad UI launcher failure was followed by a successful unweakened UI test. Physical paired-device acceptance remains unverified.

- TP-SEEK-CLOCK reopened for iPad: additional actual fullscreen seek failed in run41734974307 despite previous pass. 0.6.75 preview is not a reliable completed fix. New native-slider branch preserves all app features and investigates event order; original UI assertions retained.

## iPad native Seek candidate validation update
- Run41739107694 remained failed at pre-Seek initial caption; do not reinterpret as pass. Corrected DEBUG fixture PAUSE intent and real1s seek setup in6f26227.
- Run41741956555 now passed57 native tests plus unchanged actual fullscreen remaining/subtitle assertions after .2/.8/.5 slider adjustments. Candidate0.6.76 available unsigned. Simulator validation passed; physical-device/network/two-party field cases still open, no blanket completion claim.

## TP-IPAD-BACKGROUND-REJOIN-20261104
- Affected: iPad 0.6.78/138, source 4d6e880574307442811bca925966bd71ac2308dc. User reproduces by backgrounding app then returning/rejoining, sees connection interruption. Android behavior unverified.
- Confirmed code defect: RoomEnvelope.decode drops legitimate JSON messages over 8192 bytes; reconnect WELCOME may carry history and then never apply. Foreground event handling can miss stale WebSocket after an inactive transition.
- Candidate: branch fix/ipad-room-background-rejoin-20261104; allow bounded 1 MiB snapshots, stale-socket resume policy, new targeted XCTest. CI run 41833322017 pending; no successful fix or IPA claim until completion.
- Server: live /health HTTP 200 and process active, but room-specific auth or lease errors remain unverified due read access restrictions. No server modifications.
- Status: candidate under automated verification; physical foreground/background/connection-loss test pending.

- Evidence correction: backend snapshot() trims ordinary WELCOME history to roughly 7800 bytes. Large WELCOME rejection is a possible edge case, not a demonstrated explanation. Server reconnect with existing token passes its protocol unit test. Prior wording calling it a confirmed cause is superseded; stale client lifecycle state remains suspected.

- Follow-up CI: runs 41833322017 and 41833455531 had the same two legacy MKV caption playback assertions fail (AudioSubtitleTests lines 72/75); room reconnection tests passed both times. Run 41833459657 passed all 76 native tests and one actual fullscreen UI test with the same app-source changes, and produced verified unsigned iPad 0.6.79 IPA artifact 13324104572. Retain flakiness note; do not suppress the subtitle test.
- Status: build + simulator regression PASS in run 41833459657. Field resolution remains OPEN until the user signs/installs 0.6.79 and tests background/foreground rejoining on the same real room. Server per-room logs were inaccessible and no server contribution has been conclusively excluded. No server changes or Android changes.

- Distribution note (2026-11-04): user could not open ChatGPT sandbox IPA link and previously measured <500 KB/s over mobile hotspot through foreign download service. Isolated domestic-path alternative now staged on user's GL-MT3000 USB HTTP 49185, SHA256 verified, Range/HEAD 200/206 passed from Singapore. Real mainland hotspot speed and mobile IPv6 availability require field verification; do not claim high-speed confirmed. Existing media service config backed up and previous entries unchanged.

## TP-IPAD-BACKGROUND-REJOIN-20261104 · Reopened after field report

- User reported the connection remains interrupted after backgrounding even following the 0.6.79 candidate delivery. The screenshot shows an existing room ID and repeated automatic reconnect; installed build number and network-layer failure code are not independently verified.
- Existing source only observes `.background` and `.active`. An iPad scene that becomes `.inactive` without `.background` can retain a half-open WebSocket; all retries use `URLSession.shared`, and errors are collapsed into a generic message. These are concrete recovery/diagnostic gaps; the exact production failure remains unknown.
- Candidate 0.6.80 branch `fix/ipad-foreground-ws-recovery-20261104`: track prolonged inactivity, recreate an isolated ephemeral URLSession per transport attempt, cancel stale sessions, show categorized status codes, and provide immediate manual reconnect while keeping the room credentials. Add policy and error-message regressions.
- Read-only Singapore production check: local room service `/health` responded HTTP 200; its room telemetry and database paths explicitly returned permission denied, so no per-room authentication conclusion is possible. No backend, router, Android or production change.
- Status: candidate pending macOS CI and device acceptance. Keep 0.6.79/139 as rollback. Do not claim resolution until real iPad foreground/background and network transition tests pass.

## 2026-11-05 · iPad0.6.83 room continuity candidate
- User confirms installed0.6.80 and requests fixing intermittent room disconnect/P2P fallback stutter; Android occurrence remains unconfirmed. Verified baselinec516a142790db11ca2febf71776c0c625e9efecc, successful41841128744. Isolated fix/ipad-room-transport-continuity-083-20261105; preserve existing room identity, source/subtitle, sync thresholds, manual controls and background pause. Do not import uncompiled TLS0.82 or undeployed peer-stall changes.
- Reproduced JavaScript bug from actual bundled P2P transport: DataChannel.open followed by PeerConnection.connected emits connected and downgrades native channel state, permitting repeated15s restarts. Current state-order/fallback/recovery/stale-generation regression passes after channel-aware status normalization; baseline fails the same assertion. Add bounded15/30/60/120s retry backoff. This proves a client defect, not the cause of every physical disconnect.
- Existing foreground policy reconnects after3s inactive even with100ms-old room traffic; now use actual socket/message/handshake freshness. Genuine foreground reconnect may retain already-ready playing media/room clock for a single identity-bound8s window; retries do not renew it, expiry pauses, same-source WELCOME avoids reload/reset/seek, paused/buffering/pending controls/blocking questions do not qualify. Offline user PAUSE immediately pauses and carries only to the same room/media after calibration. Background/leave/auth failure retain pause/cleanup.
- Candidate0.6.83/build143 adds safe numeric receive/close diagnostics, native policy/P2P-backoff and real AVPlayer item/clock/manual-pause tests with generated synthetic fixture. Local JS baseline reproduction and corrected JS tests pass; diff/YAML checks pass. Apple native compilation/physical network acceptance still pending; no IPA or field-fix claim. No router/backend/config/restart or trust change.

- User clarified the acceptance criterion is preventing actual unintended room disconnection during viewing, not masking it with continued video.8s grace is secondary mitigation only. Added a direct prevention fix: a missing operation ACK after12s must expire that command and request SYNC, not close an otherwise live WebSocket. Existing baseline health test explicitly reproduces that false disconnect with fresh room traffic. Retain real receive/send errors and welcome/message-silence recovery. Add injected monotonic clock plus controller tests for healthy-room ACK timeout and actual AVPlayer pause at grace expiry. Numeric transport diagnostics remain necessary for external network failures. Production proxy read-only check found no configured stream/read/write timeout in the Together route and no recent reload event matching this report; this does not exclude home Wi-Fi/TLS path.

## 2026-11-05 · Final scope follows no-disconnect clarification
- User explicitly wants room connectivity to remain stable while viewing; temporary continued playback is not the acceptance criterion. Remove the extra8s playback-grace/offline-pause mechanism and only its generated AVPlayer fixture from this release. Existing fixture files remain intact. Restore baseline NativeTests resource discovery. Genuine transport failure/background pause/source handling stays as the verified0.80 baseline. Earlier grace-candidate notes are superseded.
- Final changes directly prevent confirmed client-triggered disconnects: healthy sockets are not reset solely for3s inactivity or a missing12s command ACK; an expired command requests SYNC without stale replay. Keep P2P DataChannel ordering normalization, status deduplication, fresh15s recovery interval after transient channel loss and bounded15/30/60/120s renegotiation backoff. Include safe numeric send/receive/close diagnostics beneath successfulHTTP101. Clock injection supports actual controller ACK-timeout tests; existing playback/source/sync regressions remain required.
- Latest device/native verification must cover this narrowed scope. No network/backend/service/DNS/TLS policy changes. Synthetic route probes and maintenance leases have ended; full-heartbeat6min IPv4/IPv6 controls pass and do not establish a physical Wi-Fi root cause. The preceding trimming script stopped while refusing to remove a pre-existing nonempty fixture directory; this follow-up completes only project/log cleanup and preserves its existing contents.

## 2026-11-05 · iPad0.6.83 verified stability build
- Final application/native-test sourceb57eb8cd39a1380c14c84f63652fb2a2b74709bb; final ARM workflowbeb719c1a81e339bc6cea07ff62dc74b727ef258 (app/tests byte-equivalent). Run42016927669 SUCCESS: unsigned iOS device build,86 native tests0 failures and actual fullscreen progress/movie-adjustment UI test PASS. All17 RoomConnectionTests and10 P2PFastPathGateTests pass. Node packaged-state ordering and independent Swift P2P/Muse handoff pass. Keep first Intel run42012686373 failure in the existing early-subtitle-selection test recorded; no assertion was weakened or skipped.
- Concrete prevention: a missing12s operation ACK no longer closes a healthy room; brief inactive scenes with fresh traffic no longer force reconnect. Correct an open DataChannel being downgraded by a later connected event; allow transient channel recovery before bounded15/30/60/120s renegotiation. Genuine transport failure/background pause retain0.80 behavior. No8s playback workaround, source/subtitle/sync threshold or server/network policy change. Actual continuous-viewing resolution on the user's iPad remains OPEN until installed and observed.
- Artifact13410148385 archiveSHA256eacf137c175868ef67ef1e7748d27ed884c4a7ef7bebd01722b096b6bfc2cc2e. Verified unsigned0.6.83/build143/dev.together.poc.asrtest, iOS-device ARM64 Mach-O platform2, bundled P2P resource matches tested SHA2563a9a8aed5a893df2d64fe5866cbb35d4fa2cafade27786ba7cb7a63dee66817d. IPA17655449B SHA2561f9ca7b9d294a2a8b723706f8714ca2a5898ec256e8976c3380d0c1d9322800a. Published only this new installer in the existing static-download service; preserve old installers/app data, no Caddy/config/service restart. Public download verification recorded after actual completion.

## 2026-11-09 · USB deletion baseline correction

User correctly identified installed iPad0.6.83. Initial0.6.59 baseline was wrong because only apple-build.yml runs were queried. That candidate branch4efc86c is superseded and run42624786296 cancelled; it must not be installed. Verified0.6.83 sourcebeb719c1a81e339bc6cea07ff62dc74b727ef258, successful device/native build42016927669, artifact13410148385; current baselinec797f3f91d045da0e06aece2764fb61fdc60ef31 only appends verification records.

New branchfeat/ipad-router-usb-delete-0683 preserves0.6.83 app/tests/resources, adds only USB native management/browser actions/3 network-result tests and candidate0.6.84/build144. Preserve TMDB toolbar action during patch merge. Private backend13985cc adds opt-in deletion;52 synthetic Python tests pass. New isolated CI inherits the delivered ARM workflow and native regression selection, adding USB management/catalog cases. No production USB changes, deployment or installation. Router current write mode is unknown: connected movie capability tool failed MCP_CONNECTION_FAILED; old read-only documentation is historical, not a current measurement. Rollback: keep0.6.83 installer and original branches; deleteEnabled remains disabled by default.

## 2026-11-09 · Native compile correction

Actions42625161921 failed in device compilation: RouterUSBManagement.swift45 assigned to the shadowing let parameter session. Corrected initializer to self.session; native tests were skipped in that failed run and remain unverified pending new CI. Router capabilities still fail MCP_CONNECTION_FAILED. No live changes.

## 2026-11-09 · Hosted ARM runner capacity failure
- Run42626638985 did not start any job step. GitHub annotation: "The job was not acquired by Runner of type hosted even after multiple attempts" and ARM capacity notices. This is runner allocation failure, not compilation/test evidence.
- Move isolated USB deletion workflow to macos-15-intel, retaining the same Xcode26 selection, generic iOS device ARM64 build, all native regressions and fullscreen UI checks. No app/test assertion changes; public app source remains25d7091. Prior baseline notes record simulator subtitle timing differences on Intel; retain existing assertions and report any actual failure.
- Router deletion production status supersedes earlier pending notes: backend7f7c14b preserves existing ext4 support, validates physical filesystemUuid, permits external GL automount alias while refusing nested mounts;53 local Python tests pass, actual USB synthetic HTTP delete passed, admin only restarted, production session reports deleteAvailable true and existing password settings preserved. No pre-existing user movies deleted. iPad installer still pending native verification.
