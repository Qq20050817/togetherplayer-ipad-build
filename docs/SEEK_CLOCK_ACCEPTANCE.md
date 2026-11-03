# Seek / clock candidate acceptance

Automatic tolerance: 3000ms. Explicit room discontinuities and local manual seek bypass tolerance. Candidate binaries remain isolated from production installs.

| Scenario | Required result | Evidence |
| --- | --- | --- |
| Steady drift at -3s, 0, +3s | No automatic hard seek or new catchup | Native policy tests |
| Lag exceeds 3s | Local rate catchup, preserve leading playback | Native policy tests; physical run pending |
| Manual 2s jump | Execute once despite tolerance | Native policy tests |
| Pending burst + PAUSE | Latest SEEK retained; PAUSE preserved | Native queue test |
| Delayed preparation + offset | Latest explicit target executed when ready | Native policy tests |
| Stale / repeated room snapshot | No reverse or duplicate jump | Native policy tests |
| Native failed seek | Bounded retry / visible failure; no fabricated playhead | Native adapter tests; hardware pending |
| Playing without ACK | Live time follows native position | Native clock/UI test |
| Fullscreen / canceled gesture | Release preview; continue native clock | Existing UI test plus field acceptance pending |
| Pause while unready | Pause intent applies immediately | Original Android unit regression retained |
| HTTP Range / USB / cloud | Actual seek result and timeout visible | Live source acceptance pending |
| Background / reconnect | No stale queued jump into replacement source | Existing session tests; physical acceptance pending |

Physical acceptance requires both devices on the same candidate protocol with local/HTTP sources, rapid forward/backward scrubs, distant jumps, repeated fullscreen/background switches and a long viewing session. Do not classify unperformed field checks as passed.

Server wait-for-peer automatic pause policy has not been deployed or verified by this client change. Existing question/explicit pause semantics remain intact.
