# Subtitle comparison 0.6.74 / Build 134 preview

Client baseline: 341feadb748bc21675915fb98deb2f4152216660. Tested client: 5d117b58f6241f9ff9685b021c6ad76aaed1708d, CI 40696932858 (device compile and native simulator regressions passed).

Fixes: selected subtitle cues are now sent before audio, retries are handled, insufficient evidence is distinct from misalignment, and short CJK dialogue plus adjacent subtitle segmentation are supported by the receiver. Subtitle timings are never automatically changed.

Known limitation: a user-confirmed aligned nine-clip real-film fixture still yields only 3 accepted semantic candidates. A larger ASR model did not improve that count, and an English translation pivot reduced it to 1, so neither change was retained as the default. Wrong-dialogue control was rejected with zero matches. The full automatic calibration goal is NOT complete. The preview must not be presented as full-film alignment verification or completed physical iPad acceptance.

The isolated app bundle and pairing namespace are retained. The unsigned IPA needs signing by the user through their existing installation method. The paired comparison endpoint is deployed separately from the existing production receiver. Generic receiver source is in server/subtitle_capture; models, credentials, deployment configuration, media, real subtitles, and raw diagnostic logs are excluded.

Rollback: stop/disable the separate comparison receiver and reinstall the previous isolated IPA. The original production listener, app namespace, and media are unchanged.
