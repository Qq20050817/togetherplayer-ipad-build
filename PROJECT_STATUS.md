# TogetherPlayer deployment status

Current deployment: **0.6.2**, branch `release/plot-polls-0.6.2`.
The `main` branches are older source baselines; do not build new releases from them.

## What changed

- Chat displays the original server `timestamp` in local time; history/reconnects preserve it.
- iPad host can create a plot question; both clients can choose a candidate or write a custom answer.
- Server conceals answers until both current members submit, rejects repeats, binds polls to the movie, and clears them after a source change.
- Apple Foundation Models on a supported iPadOS 26 device are optional. A free local template works when unavailable. Only completed, readable subtitle cues are supplied; future callbacks/open cues and subtitle/video files are not uploaded.
- Server plot state is for the active process/session. WebSocket reconnect restores it; a process restart clears active polls. Chat history remains in SQLite.

## Server

Deployed on Muse: `/home/hatch/watch-together/server/together-server`.
Service: `together-poc.service`, URL `https://together.xiaokai123.de5.net`.
Binary SHA256: `bb079552406e51ddcfb947e06c2f877a57b93606896e62d3c0d8d5150af6fa5c`.
Backup: `/home/hatch/watch-together/data/backups/plot-0.6.2-20261012-195632/`.
Original binary, source and SQLite backup retained. Do not restore the database for an ordinary binary rollback; it would discard newer messages.

Validation: full local `go test -race ./...` passed; isolated Muse instance and live two-authenticated-peer protocol checks passed (question/answer secrecy, reconnect, duplicate rejection, unchanged playback, source change, original chat timestamps). Private GitHub runner did not provide this verification; do not claim private Actions passed.

## Clients

Android: original signer SHA256 `22c413568005096f7c22464d07fe4830e36e5a8583bbf0927b022289f599b272`, ARM64, 0.6.2/build62. 45 unit tests and 24 native emulator regressions passed.
Android CI: https://github.com/Qq20050817/togetherplayer-ipad-build/actions/runs/38299901772
Android release: https://github.com/Qq20050817/togetherplayer-ipad-build/releases/tag/v0.6.2

iPad: 0.6.2/build62, unsigned IPA must be signed with the user's existing certificate. 87 core tests and 9 interface regressions passed on macOS26 / iPad simulator:
https://github.com/Qq20050817/togetherplayer-ipad-build/actions/runs/38305465767

Physical Apple Intelligence generation and the user's real tablets/movie have not been tested. Do not promise an AI accuracy guarantee.
Both clients should be updated to use plot polls; create the room on iPad and open “剧情推理” from the fullscreen tools.

iPad release: https://github.com/Qq20050817/togetherplayer-ipad-build/releases/tag/v0.6.2-ipad

Client verified source: public82e3a8fd86531579b44354bc063bc83dce9bf4dd / private91a323d09ea7fd72856dac4e42ec800411b5f03b.

New AI intelligence development is on feat/plot-intelligence-20261013 (0.6.3 trial). User explicitly prohibits further production deployment/restarts for that work. Keep Muse0.6.2 in place.
