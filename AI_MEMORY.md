# AI MEMORY

## 已核实的仓库事实

- 此仓库是公开的 TogetherPlayer iPad 构建源码及 GitHub Actions 构建仓库。
- `main` 的 README 仍介绍较早版本，不能当作最新已交付 iPad 客户端。每次根据已成功构建的 IPA、Actions、准确提交及版本文件核对基线。
- 与私有主仓库的源码可能不同步，不能自动以任一 `main` 替换已发布客户端。

## 公开仓库边界

- 禁止添加凭据、私人仓库历史、私有服务器路径、生产日志、影片、字幕、证书和用户信息。
- 保留测试、签名边界和构建流程，代码修改优先独立分支与可复现验证。

## 维护原则

记录不敏感的长期决策，实际结果参照准确构建日志和提交 SHA。

## Playback policy, 2026-11-04

- User chose 3000ms automatic synchronization tolerance. Explicit user SEEK must bypass it. Lagging clients catch up locally with speed; automatic hard-seek loops are prohibited. Pause/question gates, timeline offsets and existing P2P handoff remain authoritative.
- Coalesce only pending SEEK operations; preserve queued PAUSE/PLAY when a user drags the slider. Native playback time is the display source of truth; predicted pending seek targets must not masquerade as real time.

## HTTP recovery boundaries
- Keep consecutive HTTP retry budget separate from decoder/stall rebuild counters. Paused room ticks and same-source reload must not refill it. Two attempts with backoff/dedup; explicit retry/new source or30s actual stable advancement may start a new budget.
- Reject only explicit HTML/XHTML/JSON error response types before media extraction. Preserve absent/unknown MIME, application/octet-stream, HLS and subtitle/text compatibility to avoid new source-format false negatives.

## 2026-11-04 · Latest user clarification supersedes automatic waiting
- No automatic pause or slowdown of the leading device for drift. A lag strictly>5s must persist continuously for at least10s before catch-up starts; transient recovery<=5s, missing/invalid samples or buffering reset qualification. Active catch-up returns to normal requested speed within3s.
- User pause and explicit room SEEK remain authoritative. SEEK bypasses synchronization tolerance and persistence, is confirmed from native position, and must report failure without fabricated time. Preserve existing question/end/source identity gates.
- Android valid matched local binding is device-local priority through reconnect and transient failures. Stop old HTTP reads/preload on switch; invalid access requires a user-visible safe choice, not silent source replacement. Preserve real position/subtitles/audio and existing SAF grants.

## Decoder recovery evidence boundaries
- Decoder error alone does not establish audio versus video failure. Only audio DTS/TrueHD failures qualify for bounded same-language AC3/EAC3/AAC fallback; unknown language or unsupported tracks never silently switch language. Preserve installed0.6.60.11 sync/SEEK/local-first rules when integrating older experimental fixes.

## HTTP video recovery and delivery checkpoint
- Android installed0.6.60.11 baseline is78ea830, not old main. Verified0.6.60.12 application9354947 adds ordinary-HTTP HEVC independent recovery; its native test checkpoint387cee0 passes148 JVM+42 native, physical field acceptance open. Use parallel.decoder12 package because ephemeral CI signers differ; never require uninstalling the installed.fluency app.

## Physical video acceptance boundary
-0.6.60.12 audio recovery is user-confirmed; long Main10 picture quality failed physically despite148 JVM+42 native tests. First-frame count alone is insufficient: follow-up tests must inspect decoded output colors beyond30s and output lifecycle transitions. User's automatic room disconnect is iPad-only and home-Wi-Fi-specific, also present in old versions; investigate network path before attributing it solely to a client release.

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

## 2026-11-05 · Physical direct HTTP regression reopened
-0.6.60.13 field picture failed; local import picture/clock works, audio later confirmed volume-related and restored. Correct24fps Main10/PQ synthetic baseline reproduces gray output after fullscreen despite advancing clock.2fps fixture alone is insufficient; inspect actual composed content after aspect-fit letterboxing.
-0.6.60.14 candidate preserves synchronization thresholds, adds bounded independent HTTP input recovery at the real playhead and actual rate diagnostics. peer_stalled client support is separate from server activation; do not label paired pause/system notice active until its counterpart is deployed and accepted.

## 2026-11-05 ·0.6.60.14 verified source and release boundary
- Final appb6c1395/testd66e4d2: retain the exact active-input SurfaceTexture/native producer across fullscreen rather than calling VideoHelper.detachViews (which disables video). Explicitly release orphaned retention on real input close/replacement. Final has no GLES/RV32/hurry-up experiment; keep0.6.60.13 normal decoder configuration.
- Native42077116105 confirms149 JVM+46 native,0 failures/errors/skips; actual moving output, same producer, actual rate/normalization, HTTP recovery and existing regressions pass. Parallel42076877705 / package.decoder14/Together播放测试 delivered with independently verified signature/manifest/source/JNI/model and public full-file SHA256c9b0e21f. Physical original-film acceptance remains open.
- peer_stalled client support does not activate its server counterpart. Verified server candidate remains staged, production unchanged, and older-client canonical seek behavior requires compatible-client installation confirmation before rollout.

## 2026-11-06 · Physical Main10 gray output reopened; bounded hardware trial
- Baseline verified/delivered14 c80d0a1 (runtimeb6c1395); physical acceptance FAILED: initially normal original-film frames become corrupt even without window reparent. Safe aggregate diagnostics show software HEVC decode below movie-rate demand, zero surface restores/demux-corrupt reports; not sufficient to prove sole root cause. Audio restored through user volume adjustment. Do not publish private recording, movie, paths, telemetry or identifiers.
- New isolated15 candidate adds a capability-query-only fallback after an identified software decoder fails: PQ HEVC Main10 vendor hardware can be offered if same compressed profile/level/size/rate query passes despite missing HDR10 profile flag. Original playback Format/HDR/CSD stay unchanged. Existing two-attempt exclusion policy applies; exact-supported choices, independent fallback, working local-source behavior, retained producer, sync thresholds and audio remain. Safe codec candidate/support diagnostics distinguish actual device capability from assumptions.
- JVM gate/budget and native immutable-format/profile-map regression added. Tests/build not run yet; emulator cannot certify this device vendor driver or original movie. Production backend separately enabled after explicit user authorization and public protocol verification; advancing lag never triggers paired pause.

## 2026-11-06 ·16 real hardware trial after15 field failure
- Verified15 base5f4130d/runtime8d9281c, final153JVM12native pass and published7e525612 package; physical original playback FAILED with corruption and severe stutter. Field query proved softwareFailed=true, PQ-only probe=false, every candidate unsupported/ineligible. No hardware trial actually occurred.
-16 deliberately treats declared support as diagnostics rather than a second veto: after known software failure, bounded actual hardware trial only for clear ordinary HTTP HEVC Main10 with known positive dimensions within4K, retaining original Format/HDR/CSD. Existing selected-codec pin, two-attempt exclusions and input reset remain; trial observation resets on a new source and permits a second hardware candidate after the first fails. Actual initialization/decode decides success. Capture numeric profile/level, size/functional support and color metadata without media URLs or private identifiers. Local/audio/surface and synchronization policies unchanged; pause/resume seek origin is still investigated, not silently reinterpreted.
- JVM gate/budget/reset and native original-format/unknown-metadata/size regressions updated. Native/parallel CI pending; original physical movie acceptance remains OPEN. Original user volume issue was corrected, not a new audio defect. Private recordings/media/telemetry stay outside public repository.
