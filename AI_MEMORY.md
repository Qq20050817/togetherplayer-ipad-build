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
