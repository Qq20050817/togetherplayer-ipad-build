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
