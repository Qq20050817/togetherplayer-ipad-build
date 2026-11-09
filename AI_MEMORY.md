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
