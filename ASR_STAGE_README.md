# Isolated iPad 0.6.73 ASR preview verification

This test stays on `feat/ipad-asr-stage-073-20261026`. It does not change the official production iPad app.

* App identifier: `dev.together.poc.asrtest`, display name `Together ASR 测试`, version 0.6.73 (133).
* Nine short movie audio samples are uploaded only with explicit one-time grant to a standalone Singapore ASR listener.
* Public HTTPS endpoint: `https://tencent-sg.tail0afbde.ts.net:10000/v1/audio-capture-asr`.
* Pairing secret is obtained privately. It is never embedded in the public IPA.
* Native regression tests, app Info.plist checks, SHA256, and public **prerelease** publish must succeed before recommending the IPA to the user.
* IPA is unsigned and must be signed with the matching Apple provisioning profile before installing side-by-side.
* Audio is transcribed in memory; staging listener writes no movie audio files. Actual subtitle alignment remains a subsequent acceptance test.
* Existing 8768, 18731, and other production services remain untouched.

Deployment staging listener launched as a temporary 24-hour low-priority process. Do not present it as a persistent system service or rotate current official credentials.
