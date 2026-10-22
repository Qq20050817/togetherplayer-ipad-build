# Watch memory and recommendations 0.6.60

Status: implementation and targeted verification in progress. Do not describe this as a tested physical-device release until CI passes.

## Baselines and recovery

- iPad: Qq20050817/togetherplayer-ipad-build, d017f9277480e5f78a2b762b0942a96dac519611 (0.6.59 build119), latest successful delivery run 39691535605; source CI 39690482361.
- Android: same repository, 89a28b1bf5fb4952393a5f6a7f73b8a7706399e4, latest successful build 39684959814, source version 0.6.58.
- Main private repo main is older (7bc1cca), so it is not used to overwrite either client.
- Current server has independent deployment and is unchanged. No server or router restart, migration, or deployment is required. Existing active-room lease source branch b995bb3 remains outside this change.
- Independent branches: feat/ipad-watch-memory-recommendations-20261022 and feat/android-watch-memory-recommendations-20261022.
- To recover, reinstall the prior corresponding installer without clearing application data. No main merge, force push or deletion of existing history.

## Behavior

An independent watch-memory-v1 archive retains completed title, stable movie identity, completion time, score, tags, notes and dismissed recommendations. File cleanup, subtitle cleanup and disconnect handlers never delete that archive. Updates retain it; uninstalling or clearing app storage can erase it. Histories are device-local and are not shared with the other room participant.

Completion requires at least 70% unique continuous watched coverage and reaching the last three seconds. Position jumps, buffering, repeated intervals and source switches cannot create coverage. iPad also accepts an already completed matching story-end report. Manual marking supports skipped credits, older watched titles and uncertain detection. Coverage checkpoints during an incomplete viewing session are currently in-memory; completed records survive relaunch.

Recommendation cards include a premise, recommendation reason and specific tag/history relation. Scores 4 and 5 increase tag weights, 1 and 2 decrease them. Unrated completion is only a weak signal and is never described as liking a film. Free-text notes are preserved for the user; ranking uses explicit tags and scores. Seen and dismissed films are excluded. An empty history does not pretend to be personalized. Unknown titles are retained without inventing metadata and can be tagged manually.

48 authored seed entries work offline. Apple public genre feeds refresh up to two positively weighted genres and cache discovered metadata. Failure retains history and cached recommendations. This is genre-based candidate discovery rather than semantic full-plot analysis. Online cards link to Apple metadata; live source plots can be longer and region-dependent. Only genre IDs are queried for online discovery, with no credentials or full history upload.

## Validation

Targeted tests cover source deletion plus relaunch, rating and note persistence, duplicate Chinese/English titles, remake year discrimination, seen/dismissed filtering, positive and negative feedback, cold start, seeking/buffering/source switches, repeated intervals, natural ending and corrupt archive preservation. CI builds actual applications and packages installers only after targeted native checks. iPad UI tests open the real new page and save a record.

Full two-device playback and physical iPad/Android installation remain to be verified on hardware. Existing network and playback features are not intentionally changed.
