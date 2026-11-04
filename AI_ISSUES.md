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
