# Playback acceptance — final clarified policy, 2026-11-04

Ordinary drift never issues PAUSE or SEEK. Pause belongs to users; existing explicit blocking-question and media-end lifecycle remains protected.

| Scenario | Required behavior | Verification |
| --- | --- | --- |
| Lag <=3s | Normal requested playback rate | Native policy tests |
| Lag 3–5s before catch-up | Normal rate; no new catch-up | Native policy tests |
| Lag exactly5s | Must not start the persistence window | Native boundary tests |
| Lag >5s for less than10s | Normal rate | Native persistence tests |
| Lag >5s continuously for at least10s | Only the lagging device accelerates | Native persistence/integration tests |
| Error returns to<=5s before activation | Clear/restart qualifying window | Native interruption tests |
| Missing/invalid native samples or buffering | Must not count as continuous excess drift | Native sample/readiness tests |
| Active catch-up returns within3s | Restore normal requested rate | Native hysteresis tests |
| Device ahead by5/9/10/11/20s | Keep playing; no automatic pause, backward SEEK or slow-down | Native leading-device tests |
| Manual2s SEEK, including during catch-up | Execute despite thresholds; once per new room discontinuity | Native queue/policy tests |
| Burst/delayed preparation/offset/stale snapshot | Newest valid explicit target; preserve PAUSE/PLAY | Preserved native regressions |
| Android ordinary server-driven SEEK | Native-position confirmation and bounded failure feedback | New real HTTP paused-room regression |
| Native ignored/failed SEEK | Clear failure feedback; UI retains actual position | Android deadline regression; iPad adapter checks |
| Normal playback and fullscreen drag/cancel | Native time continues; no stuck drag preview | Existing clock/slider/UI regressions |
| Valid Android matched local file | Local only; no HTTP reads/preload after switch/reconnect/renewed URL/retry | Real HTTP/local request-count test |
| Missing local file / invalid grant | Prompt reselect; no silent HTTP switch; explicit unbind permits USB fallback | Native deleted-file/grant tests |
| Peer buffering/fault/disconnect | Healthy participant keeps playing; no canonical pause/rewind/version change | Server84-test suite and local/public two-connection protocol check |
| Explicit user PAUSE / room SEEK | Preserve pause; broadcast SEEK to both | Server/live protocol tests |
| Initial Baidu identity, blocking questions and end | Preserve existing gates and lifecycle | Server regression suite |

Physical two-device video playback, hardware-format combinations and long viewing sessions remain unverified: Windows/Muse device-control connections are unavailable. Protocol tests use synthetic rooms and actual WebSocket connections; they do not establish real-device video decode acceptance.

Verified android delivery: 0.6.60.10/130, source64aba059ab087c562f0718628ab28d0d6208c3c3, Actions41812565306. 142 JVM tests +40 native emulator tests;0 failures/errors/ignored/skips. New real HTTP ordinary SEEK confirmation/ignored-seek deadline, deleted-local-file, no duplicate HTTP after local/reconnect/renewed URL/retry, explicit unbind/grant checks pass.
Installable SHA2562753e73c61eed20aef104e78a51be0d74274bcad3b58259ac348192be40b389e. Previous candidates retained as history; this supersedes their automatic-wait behavior.
