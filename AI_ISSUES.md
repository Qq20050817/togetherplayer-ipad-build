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

## 2026-11-05 · Android-only continuation
- User reports iOS resolved and requests only the Android build. Stop iOS investigation and builds.
- 0.6.60.13 run41871520730 compiled and passed unit tests but failed its new first TextureView color read immediately after decoder READY. Do not call native validation passed. Start playback before the first timed color sample (2.5s), retaining repeated color, duration and reparent assertions, and report actual RGB on failure. Full regression pending.
- Build parallel `.decoder13` / Together 画面测试 to preserve both installed apps and their data; complete app source is checked against a7aba03. No sync change.

## 2026-11-05 · Output candidate correction
- d29235f package41995109164 built and coinstalled successfully, but native41995108894 fails actual composed color after fullscreen reparent. Its synthetic screenshot shows black video at13s while controls remain visible. This is a real TextureView lifecycle regression, not a passing candidate. Do not deliver that APK.
- Revert only TextureView output to the previously verified SurfaceView path; retain decoder-owned Main10 reference pictures via avcodec-dr=0. Keep the same long actual-screen color/fullscreen/clock assertions. Original-film gray corruption remains physically unverified. No audio/sync/iOS app changes.
- User confirms the intermittent room disconnect/P2P fallback stutter on iPad only; Android occurrence unknown. Earlier create/join iOS failure resolved per user. Keep these iPad symptoms separate and open while completing requested Android build.

## 2026-11-05 · Main10 fixture scope correction
- Native41997134244 still fails after fullscreen: videoTrack=-1, attached=true, playing=false at13s. The synthetic fixture has only video; removing that sole track during reparent can end LibVLC input before surfaces return. Merely enabling on surface-ready did not solve it. Do not claim that patch works. Existing real-film and embedded-subtitle fixtures have audio.
- Retain final application behavior f650ad1 (SurfaceView + avcodec-dr=0 only), withdraw the unverified explicit track-enable change. Add a generated silent stereo AAC stream to the same bitstream-copied48s Main10 test to represent the audio/video movie case. Preserve every actual-screen color, fullscreen, native-clock and pause assertion. Video-only fullscreen remains a separately observed preexisting edge case, not covered as fixed. New candidate tests pending.

## 2026-11-05 · Gray output reproduced with audio/video fixture
- Native41998138202 passes fullscreen entry but actual composed output turns gray/corrupt after return at25.9s (videoTrack=0, attached=true, playing=true). Synthetic screenshot resembles reported gray corruption; desktop software decode at25s stays colored. DR0 alone with SurfaceView is insufficient for this output transition. Do not deliver it as fixed.
- Earlier TextureView fullscreen black result used video-only input that ended when its sole track detached. It did not isolate TextureView behavior; previous texture-only causal wording is superseded. Reevaluate applicationa7aba03 (TextureView+DR0, unchanged audio/sync) using the same Main10 bitstream with silent AAC and unchanged composed-screen/fullscreen/color assertions. This is a candidate pending new native/physical validation.

## 2026-11-05 · Android0.6.60.13 final verified delivery
- Final applicationa7aba03f0be4afe79730f84a295a3a314e3f38ce (TextureView initial/rebind + avcodec-dr=0), test/packaging checkpoint590646e4f0e4a53994ea7c44bedd8bfb326fe035. Full application Java/resources byte-equivalent check passed. Audio/sync behavior preserved.
- Native41998995493 SUCCESS: JVM tests/build, scoped Main10 color case, full43 native tests, compact ARM64 build and upload. Independently extracted native XML confirms43 tests,0 failures/errors/skips. Actual composed colors remain correct beyond30s and through fullscreen enter/return on synthetic Main10+AAC fixture. SurfaceView comparison41998138202 previously reproduced gray corruption after return; video-only fixture early ending is a separate open edge case.
- Parallel41998995494 SUCCESS, artifact13401274159, archiveSHA25649c6d8a5c7fe3bdef3ba28bea1fb0ae7d717b0832370772692f2201478e3f09d. APK78562653B, SHA256f8ed5904a286fa0b465a25ed47a93fef427ec1d32055d96d4e50aefdcdade5ea;0.6.60.13/build133/dev.together.poc.decoder13/Together画面测试. ARM64/compressedJNI/offline model integrity, real coinstallation+launch passed.
- Published only this new standalone installer using the existing download service. HTTP206 and complete public download78562653B independently match SHA256. Older installers/apps/data preserved; no service configuration/restart, backend, iOS or router change. Physical Pad7 original-film/HDR/performance acceptance remains OPEN; do not claim the actual user movie fixed until tested.
- Initial iOS create/join issue is user-reported resolved. Later intermittent iPad room disconnect/P2P fallback stutter remains open, Android occurrence unconfirmed. This Android package does not add the separate undeployed10s frozen-progress paired pause/system danmaku feature.

## TP-ANDROID-DIRECT-MAIN10-0613-REOPEN
- Physical acceptance FAILED: direct USB HTTP corrupt picture despite advancing progress; passive viewing can show seek-confirmation warning. Local import picture/progress works. User later confirms sound restored after correcting volume, so do not introduce speculative audio changes.
- Cause not established. Existing2fps silent synthetic validation did not cover movie-rate load. New24fps generated audiovisual/seek baseline regression pending. Application remains verified0.6.60.13 unchanged during reproduction.

### TP-ANDROID-DIRECT-MAIN10-0613-REOPEN · verified candidate0.6.60.14
- Synthetic24fps baseline reproduces gray output after fullscreen; active reparent currently destroys TextureView output and VideoHelper disables the video track. Finalb6c1395 preserves the same producer and bounds independent HTTP recovery without peer-time jumps. Failed hurry-up/GLES approaches were withdrawn.
- Native42077116105:149 JVM+46 native0 failures/errors/skips, including repeated actual composed colors/motion/frame advancement and producer identity through fullscreen/return plus real rate correction. Final parallel APKc9b0e21f and full public download verified. Status: automated regression PASS; original-film/device/WAN physical acceptance OPEN.
- Audio issue was corrected by user volume adjustment. Service-side frozen-progress pause/assistant notices are prepared separately and are NOT enabled merely by installing this APK; require compatible-client confirmation and the recorded server release step.

## 2026-11-06 · Physical Main10 gray output reopened; bounded hardware trial
- Baseline verified/delivered14 c80d0a1 (runtimeb6c1395); physical acceptance FAILED: initially normal original-film frames become corrupt even without window reparent. Safe aggregate diagnostics show software HEVC decode below movie-rate demand, zero surface restores/demux-corrupt reports; not sufficient to prove sole root cause. Audio restored through user volume adjustment. Do not publish private recording, movie, paths, telemetry or identifiers.
- New isolated15 candidate adds a capability-query-only fallback after an identified software decoder fails: PQ HEVC Main10 vendor hardware can be offered if same compressed profile/level/size/rate query passes despite missing HDR10 profile flag. Original playback Format/HDR/CSD stay unchanged. Existing two-attempt exclusion policy applies; exact-supported choices, independent fallback, working local-source behavior, retained producer, sync thresholds and audio remain. Safe codec candidate/support diagnostics distinguish actual device capability from assumptions.
- JVM gate/budget and native immutable-format/profile-map regression added. Tests/build not run yet; emulator cannot certify this device vendor driver or original movie. Production backend separately enabled after explicit user authorization and public protocol verification; advancing lag never triggers paired pause.

## 2026-11-06 ·0.6.60.15 actual verification and physical failure
- Final runtime8d9281c / parallel2e4b7ea:42090953639 success, independently verified APK78570173B SHA2567e52561282c7eecbe0a08c5c7bb739857934877d381134b51160f8ff1fa32f97, package.decoder15/version135/Together硬解测试, APKv2 signature/content/AXML/ARM64/model and public HEAD200/Range206/fullhash pass. Old14 retained, no service restart.
-153 JVM+12 focused native pass. First workflow42090953702 failed only after passing tests due cross-shell result variable; fixed workflow5f4130d,42092370345 SUCCESS, independently verified final report. Previous c14ecf2 complete152JVM+48native pass remains separately attributed.
- Physical15 acceptance FAILED: fresh version15 diagnostics and second recording show zero-time preparation, repeated stalled-progress pauses, later corruption and severe stutter. New safe query diagnostics prove known software failure, every hardware candidate ineligible, PQ probe false, so actual hardware trial never occurred. Do not treat automated pass as physical repair. Original audio-volume issue remains user-corrected. No recording/movie/private telemetry enters public repository. Follow-up16 will try actual hardware within bounded recovery instead of gating again on failed declarations. Pause/resume jump origin remains under investigation; preserve explicit user seek semantics.

## 2026-11-06 ·16 real hardware trial after15 field failure
- Verified15 base5f4130d/runtime8d9281c, final153JVM12native pass and published7e525612 package; physical original playback FAILED with corruption and severe stutter. Field query proved softwareFailed=true, PQ-only probe=false, every candidate unsupported/ineligible. No hardware trial actually occurred.
-16 deliberately treats declared support as diagnostics rather than a second veto: after known software failure, bounded actual hardware trial only for clear ordinary HTTP HEVC Main10 with known positive dimensions within4K, retaining original Format/HDR/CSD. Existing selected-codec pin, two-attempt exclusions and input reset remain; trial observation resets on a new source and permits a second hardware candidate after the first fails. Actual initialization/decode decides success. Capture numeric profile/level, size/functional support and color metadata without media URLs or private identifiers. Local/audio/surface and synchronization policies unchanged; pause/resume seek origin is still investigated, not silently reinterpreted.
- JVM gate/budget/reset and native original-format/unknown-metadata/size regressions updated. Native/parallel CI pending; original physical movie acceptance remains OPEN. Original user volume issue was corrected, not a new audio defect. Private recordings/media/telemetry stay outside public repository.

## TP-ANDROID-HDR10-HARDWARE-SURFACE-0617 · OPEN
- User confirms the same original film plays from Xunlei cloud on Xiaomi Pad 7. Cloud playback has different transport and decoder choice; this does not prove router HTTP or app root cause alone.
- Confirmed source limitation: independent LibVLC recovery previously forced software with `setHWDecoderEnabled(false,false)` and `:codec=avcodec`, output through TextureView. Physical 4K Main10 software throughput was insufficient; Android notes TextureView HDR may lose dynamic-range detail through SDR conversion.
- Candidate `fix/android-hevc-hdr10-surface-trial-0617-20261106` from `41c8d6d7fa7a24036a2b9d7c72e9377774e98cfd`: conditional LibVLC MediaCodec/SurfaceView for explicit ordinary HTTP failed decoder with real ST2084, known HEVC Main10 <=4K. Original Format/HDR/CSD, local/SDR routes and room controls retained.
- Added JVM gating and native output-selection coverage without weakening original strict Main10 tests. Build/CI, actual hardware selection, original device HDR passthrough and long-play acceptance **OPEN**. No delivery, merge or deployment.

- CI `42112799811`: unit/compile PASS, 14/16 native PASS. The old software 24fps case still corrupts after 27.5s; new HDR selector test hit a harness-only `NetworkOnMainThreadException` due to `MockWebServer.url` being read inside Android's UI-thread callback. The test fixture URL is now acquired before `onActivity`, and the selector will be independently tested before the full strict regression. No runtime fix is established by this harness repair.

- 2026-11-06 verification: workflow `42114420724` successfully tested HDR10 SurfaceView route selection (1/1) and full targeted native group (16/16), but unchanged strict software TextureView movie-rate color repeat 1 still FAILED with actual gray chroma at 29.67s. Keep issue OPEN, do not weaken/remove legacy regression. Workflow `42115811152` passed isolated emulator install and ARM64-only diagnostic build, SHA `bfa4585c7abd45094cf76a4c67fcc059e32016ff8b9611d71b26803382aff9e6`; real Xiaomi Pad 7 HDR rendition, ability to use hardware path after HTTP failure, fullscreen/seek/subtitle stability remain unverified. Use parallel install `dev.together.poc.hdrtrial17` for field test, preserve production package; uninstall trial only to revert. Delivery over user USB HTTP still pending verification.

## TP-ANDROID-HDR17-GRAY-OUTPUT-FIELD-20261106 · OPEN

- Real Pad 7 feedback: the independent 0.6.60.17 diagnostic player was tried once and playback remains incorrect; the user did not observe the transient HDR selection message. Mark physical acceptance FAILED by user report; actual vendor decoder selected and HDR output are UNKNOWN.
- Verified source gap: `CompatiblePlayback` previously declared ready after just one reported frame. Once active, a gray picture with advancing frame/clock count has no pixel-integrity detector and does not trigger the ExoPlayer error-only recovery path. In the unchanged emulator software path, the strict Main10 movie-rate chroma test fails around 30s.
- Verified diagnostic gap: the bounded private `PlaybackDiagnosticJournal` allowlist stripped `hdrHardwareSurfaceRequested`, `boundedHardwareTrial`, `colorTransfer` and `colorSpace`. Existing Singapore server stdout does not establish which decoder the device chose.
- Candidate branch `fix/android-hdr10-hardware-only-diagnostics-20261106`, based on `cfff31f0b4064cc355f6a0321df216b7ae7c2480`, safely admits an explicit HEVC + ST2084 <=4K post-failure hardware trial when the optional RFC6381 codec string is absent, rejects an explicit non-Main10 profile, waits for three frames on this HDR branch only, detects ten seconds of genuine no-frame progress while actively playing, and preserves safe HDR flag diagnostics. Existing local/SDR one-frame readiness is unchanged.
- Safety boundary: this candidate does not inspect private video pixels, does not assert hardware decode or picture quality merely from frame counts, and does not change server/router/iPad or production installations. Workflow 42227399707 pending at initial log. Source segments previously FFmpeg-decoded clean; router HTTP bandwidth and physical hardware output remain separate unresolved checks.


## 2026-11-06 · OPEN: HEVC Main10 color presentation and real Pad 7 HDR

- User-confirmed .17 Pad 7 original-film result remains bad even though the exact-sized film plays from Xunlei cloud in original quality. A working player on the same tablet is evidence of some working decoding/display pipeline, with potential differences in native codec path and transport. Current experimental branch has NO validated Pad 7 correction.
- CI 42227399707: native HDR routing/SurfaceView test PASS, unchanged strict 24fps Main10 native color test FAIL; compilation and all JVM tests PASS.
- CI 42229242735: failure-only added screen/texture sampling shows visible screen stripe flat gray `0xFF888888` and `TextureView` underlying image black `0xFF000000` while VLC reports selected video, attached output, playing, advancing decoded/displayed counts and active audio. `surfaceRestores=1`; the gray/black state occurs around position 16.87s after fullscreen reparent. This is presentation evidence, not proof of bitstream corruption or vendor codec identity.
- CI 42230535321: one-time native output rebind trial failed to restore correct stripes; same pixel mismatch. That code was **reverted** in commit 6588cac40ae5ec14f28d514a25b619582c2f6eb4. Keep original strict threshold and native color test red.
- Next safe acceptance needs an actual device HDR output test, distinct selected decoder evidence where technically available, and real post-fullscreen/seek colored frames. This can require a separately authorized experimental Android install; no new APK or production update has been delivered. Current candidate is **NOT VERIFIED / NOT READY**.


## TP-ANDROID-HDR-DEVICE-REPORT-20261106

- Status: **OPEN / awaiting device evidence**. Scope: Android original HDR video renders gray, black or mosaic in TogetherPlayer, while the same source can play at original quality in another player on the same tablet. Source transport, actual decoder selection and Surface/Texture rendering need separate confirmation.
- Verified emulator evidence: a strict 24fps Main10 picture regression has gray composed output with black TextureView despite progressing native frame counters. Prior one-time rebind experiment failed and was reverted; do not silently enable it.
- Separate diagnostics branch `feat/android-hdr19-device-export-20261106`, code commit `bd09c78767d71f648a78240acbeb00074cc39d8b`, APK 0.6.60.19 package `dev.together.poc.hdrdiag19`. CI **42239338504 SUCCESS**, real tablet picture test pending. User-triggered, local-only sanitized report records actual decoder if observed, HDR video format, surface lifecycle counters, and candidate codec capabilities clearly labelled as candidates.
- APK USB HTTP delivery verified externally: HEAD 200, HTTP Range 206/1024 bytes, old route HEAD 200, unspecified path 404. Delivery does not establish that physical HDR video rendering is fixed.
- Next: collect Android tablet local report after reproducing problem, inspect vendor decoder/Media3 versus VLC paths and surface events, devise narrowly scoped source fix, verify strict native color regression and physical HDR output before release. Do not modify production app or transcode original HDR during diagnosis.


### 2026-11-06 · Real device JSON received, decoder failure sequence confirmed

- Status remains **OPEN**. Physical Android 15 HTTP HEVC Main10 3840x1600 two independent attempts: software decoder `ERROR_CODE_DECODING_FAILED`, Qualcomm regular and low-latency HEVC decoders both `ERROR_CODE_DECODER_INIT_FAILED`; fallback recorded `hdrHardwareSurfaceRequested=false` twice. The locally exported current VLC state was paused/buffering with no displayed frames.
- Source confirmation: fallback requires `colorTransfer==ST2084`; when that transfer marker is absent, code currently selects VLC forced software avcodec/TextureView despite known Main10 codec string. First fallback only reported 396 displayed pictures after ~70s, without pixel/color verification. Capability list queried 3840x2160@24 while source was 3840x1600; advertised booleans are not authoritative hardware incompatibility proof.
- Isolated source candidate `fix/android-hdr-missing-transfer-trial-0620-20261106` broadens only the post-failure Main10 missing-transfer case to try VLC hardware+SurfaceView. Explicit SDR/HLG and non-Main10 remain guarded. CI **42246216693** pending; no APK deployed, no claimed physical playback repair. If trial fails, collect device-side codec exception details and picture evidence before another change.


### 2026-11-07 · HDR20 limited hardware fallback candidate available, field outcome unknown

- The real-device symptom remains **OPEN**. New bounded policy addresses a confirmed selection gap: with known HEVC Main10 and absent transfer marker after failed Media3 decoders, use VLC MediaCodec hardware/SurfaceView while preserving original compressed source. Explicit SDR/HLG and non-Main10 excluded.
- Initial run **42246216693** failed on an unresolved Media3 transfer constant, fixed before packaging. Repeat run **42246662174 SUCCESS** with JVM regression, API35 emulator diagnostic UI, separate install identity, ARM64-only packaging and SHA verification. APK 0.6.60.20 SHA256 `0220a75031fd4733c33f24f787c5cfe4d380743c0bcee74339132254a19f1a56` staged to USB HTTP; remote HEAD200/Range206, earlier route HEAD200. No production app update.
- Remaining uncertainty: actual Qualcomm hardware decoder initialization may still fail; original Media3 codec error causes are not yet captured in this export. If device playback remains gray/black, capture new report while playing and include video/screen observation. Do not close before real HDR colored-frame verification and playback recovery checks.


## ANDROID-HDR21-INIT · 2026-11-12 · Investigating

- Affected baseline:0.6.60.20, implementation9ac8b9124d13696a7d9dd10e59ebd3fb29feac9a, successful build42246662174; documentation checkpoint24b5e6ecd9c17db59ed8d4c4ac8af72fdf59820a. User confirms this installed version.
- Symptoms: original HEVC Main10 playback corrupts or goes black while time may advance. User recordings inspected privately; no recording, movie title, source URI or private content committed. User reports clean Xunlei and earlier4K/HDR playback, so hardware incapability is not established.
- Code evidence: Media3 1.7.1 defaults to asynchronous MediaCodec on Android12+. Existing bounded recovery changes codec names while retaining configuration/API choices. Synchronous minimal configuration is an unverified compatibility hypothesis, not an established cause of vendor initialization errors.
- Candidate: add one same-codec synchronous retry after initialization failure, remove only optional allocation/scheduling hints, preserve compressed/HDR/output data, retain numeric safe codec exception facts. Test default success, immutable CSD/HDR/Surface, single retry, failure propagation and exclusions.
- Status: code prepared; compilation, instrumentation, unchanged strict picture gate and physical original-film acceptance pending. VLC3 independently has a late-block discard outside its hurry-up guard; this candidate does not claim to patch or fix that native software path.


### 2026-11-12 · HDR21 validation update: codec logic passed; original picture remains OPEN

- Local application/test APK assembly and162 JVM tests passed. All5 focused Android35 instrumentation cases passed after precompiling the package to resolve an environment startup ANR; test assertions were unchanged and adapter initialization failures are injected.
- A user-approved bounded original-coded sample was verified end-to-end and strictly decoded on the host (1080 frames and audio,0 errors). The Android operational HTTP harness completed, but actual screenshot acceptance DID NOT pass: software emulation produced a SystemUI ANR, virtual goldfish runtime decoding failure followed by compatibility playback, large video/clock lag and111 late compressed-block drops. No physical Qualcomm initialization-failure event was exercised by this replay.
- Two paused seeks confirmed native time and advancing display counters, but screenshots still showed stale/earlier content compared with independent reference frames. This is not proof of correct target-time pixels. Cause may involve the software-emulated output pipeline; do not claim a physical output repair. The original unchanged strict picture CI is still queued during the GitHub Actions major outage.
- Source changes remain a bounded hardware-initialization compatibility candidate with safe failure evidence. No new stable release or existing-client replacement. Physical original4K HDR playback/driver verification remains required; target tablet is not currently connected.
- Also corrected the observed cropped4K badge: width3840/height1604 was labelled1080p by the previous height-only check. Inspect width as well as height; actual compressed source and HDR metadata remain unchanged.


### 2026-11-12 · HDR21 final verification: build/native logic pass; picture gate FAILED

- Final runtime source `cbfb49c`; local162 JVM tests PASS. CI43108947930 `package-diagnostic` SUCCESS with all10 selected Android35 tests and final ARM64 package checks. The5 hardware-retry cases use injected initialization failures and do not exercise a physical vendor driver.
- The unchanged strict24fps Main10 color test actually ran and FAILED at20,720ms:matches0, composed gray/underlying texture black,885 decoded/218 displayed frames. Aggregate CI is FAILURE. This corrects the earlier queued/outage checkpoint; neither a compiling APK nor the native test group closes the picture issue.
- Keep status OPEN / awaiting actual Qualcomm tablet picture and safe error facts. The independent0.6.60.21 package is a compatibility experiment, not a validated replacement or stable repair. Original-sample Android image acceptance also remains unpassed; private temporary copies were removed.
