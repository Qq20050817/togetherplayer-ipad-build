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

- TP-ANDROID-USB-HTTP: local router Range boundary probes passed for available large MKV / small MP4. No evidence of 4GB integer truncation in this server. Cross-network throughput and large MP4 remain unverified.
- TP-ANDROID-LOCAL-FIRST: confirmed source-path gap: normal HTTP local-file selections bypass identity checks, and default source switching may clear external subtitles. New phase will preserve prior reconnect fail-closed behavior.

## HTTP error pages reported as unsupported movie format
- Confirmed factory review: default normal/Baidu HTTP paths had no content MIME predicate.200 HTML/JSON could reach the extractor and appear as malformed/unsupported container. Candidate0999f58 rejects explicit structured error MIME, retains unknown/generic binary/HLS/subtitle variants. Real Media3/MockWebServer and unit regressions added; run41742801175 pending, not marked fixed in delivery.

## Automatic retry budget reset by paused room
- Confirmed shared playerRebuildCount reset on paused tick; continuous HTTP errors could regain retries. Candidate9a36b3f introduces separate two-attempt budget, scheduled dedup,30s actual advancing recovery reset and explicit retry/new-source reset. Pause/same-source load cannot refill it. Policy tests added; full candidate CI pending.

## Android candidate regression results
- Run41742801175 passed137 JVM plus38 native tests with0 skipped/failed. The historic picker-after-WELCOME assertion now passes against real matching HTTP bytes; identity gate unchanged. Error-page classification and retry-budget tests passed. Candidate0.6.60.8 available for field validation, superseding partial/superseded runs.
- Field hardware/long-duration/mobile-network matrix remains open. Backend optional source-fault isolation needs separate authorized deployment. >10s pause-intent classification remains outstanding and must not be declared complete.

## SYNC-SUSTAINED-CATCHUP · 2026-11-04
- Problem: immediate correction and automatic wait/pause conflicted with the final user requirement. Root: instantaneous error thresholds plus peer-readiness shared PAUSE and a mistaken local >10s auto-pause.
- Final application64aba059ab087c562f0718628ab28d0d6208c3c3: lag>5s continuously>=10s before local rate correction; no automatic pause/seek; settle within3s. Native boundary/interruption/reset/manual-control regressions pass in Actions41812565306. Server peer-pause removed/deployed with84 tests and live public protocol proof.
- Status: native/emulator/control-protocol verified; physical playback/long field tests unverified.

## ANDROID-ORDINARY-SEEK-CONFIRM · 2026-11-04
- Source audit: normal server-driven seeks went directly from Media3Adapter to Player, bypassing the UI native-position confirmation/15s failure tracker used by instant controls. Route them through seekManually. Real paused-room HTTP seek now confirms, and a simulated ignored native request reports failure while clock/playhead remain real. New native test passes in41812565306. Existing local/SAF/compatibility/rapid-seek/clock regressions retained.

## TP-ANDROID-USB-DECODER-20261104 (open)
- Installed0.6.60.11: router USB HTTP movie reports ERROR_CODE_DECODING_FAILED. Exact failed renderer unknown; prior media evidence suggests HEVC Main10/DTS compatibility risks. Candidate0.6.60.12 distinguishes renderer/MIME/decoder, adds once-per-source same-language compatible audio recovery on DTS/TrueHD audio failure. Native verification and real Pad7 movie acceptance pending.

## TP-IOS-080-WIFI-TLS-20261104 (open)
- Installed0.6.80: room secure connection fails on home Wi-Fi, works on phone hotspot. DNS automatic, proxy off, no iPad VPN (user confirmed). External server health/TLS pass; exact home path unconfirmed. No TLS validation bypass, DNS/router mutation or speculative iOS release.

## TP-ANDROID-HTTP-HEVC-RECOVERY-0612 · Native verified, physical acceptance OPEN
- Confirmed source gap: HTTP playback could not enter the independently bundled HEVC software path, which only accepted file/content. User's installed0.6.60.11 failed on router HTTP and English Dolby Digital switching did not restore playback; actual failed renderer remains unobserved on the device.
- Application9354947 enables explicit ordinary-HTTP recovery after actual HEVC runtime failure/exhausted OS alternatives, excludes account/header/URI-credential sources, preserves native position/subtitle/pause intent, and clears fault on actual independent READY. New source-policy and HTTP Main10 native regression now pass (test checkpoint387cee0, run41861295638).148 JVM+42 native0 failures/errors/skips, plus scoped Main10 test. Physical Pad7 original-film/HDR/performance acceptance remains open.
- Parallel packaging cb62178/run41859361593 preserves application code and verified coexistence with prior.fluency identity; package.decoder12 / Together解码测试. Existing0.6.60.11 remains intact; user must enter/select a room in the independent test app. No uninstall/migration.

## TP-ANDROID-MAIN10-CORRUPTION-0612 · OPEN
- Field0.6.60.12: sound works, gray/block/tearing corruption develops after initially good picture. Screenshot around00:34; occurs without floating windows. Independent HTTP decode confirmed by sanitized code-only telemetry; bounded same-source desktop frames are clean.
- Candidate0.6.60.13 tests TextureView output plus decoder-owned reference buffers, preserving audio/source/sync. Add actual long-running color validation and output reparenting; build/field acceptance pending. Never mark0.6.60.12 picture quality accepted from its earlier frame-count test.
