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

## 2026-11-05 · iPad0.6.83 room continuity candidate
- User confirms installed0.6.80 and requests fixing intermittent room disconnect/P2P fallback stutter; Android occurrence remains unconfirmed. Verified baselinec516a142790db11ca2febf71776c0c625e9efecc, successful41841128744. Isolated fix/ipad-room-transport-continuity-083-20261105; preserve existing room identity, source/subtitle, sync thresholds, manual controls and background pause. Do not import uncompiled TLS0.82 or undeployed peer-stall changes.
- Reproduced JavaScript bug from actual bundled P2P transport: DataChannel.open followed by PeerConnection.connected emits connected and downgrades native channel state, permitting repeated15s restarts. Current state-order/fallback/recovery/stale-generation regression passes after channel-aware status normalization; baseline fails the same assertion. Add bounded15/30/60/120s retry backoff. This proves a client defect, not the cause of every physical disconnect.
- Existing foreground policy reconnects after3s inactive even with100ms-old room traffic; now use actual socket/message/handshake freshness. Genuine foreground reconnect may retain already-ready playing media/room clock for a single identity-bound8s window; retries do not renew it, expiry pauses, same-source WELCOME avoids reload/reset/seek, paused/buffering/pending controls/blocking questions do not qualify. Offline user PAUSE immediately pauses and carries only to the same room/media after calibration. Background/leave/auth failure retain pause/cleanup.
- Candidate0.6.83/build143 adds safe numeric receive/close diagnostics, native policy/P2P-backoff and real AVPlayer item/clock/manual-pause tests with generated synthetic fixture. Local JS baseline reproduction and corrected JS tests pass; diff/YAML checks pass. Apple native compilation/physical network acceptance still pending; no IPA or field-fix claim. No router/backend/config/restart or trust change.
