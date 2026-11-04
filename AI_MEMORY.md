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

## Automatic room stall pause contract
- Only fresh periodic real-player position reports may indicate a 10-second stall. A behind but advancing member uses local speed correction. Server `peer_stalled` PAUSE must preserve each client's actual playhead, avoiding skipped scenes on the stalled peer; manual resume retains catch-up. This rule is separate from explicit user PAUSE, question gates and stale/disconnected status.
