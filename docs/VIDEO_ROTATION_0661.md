# TogetherPlayer 0.6.61 combined preview

Scope: preserve 0.6.60 watch memory and explained recommendations, add local quarter-turn picture rotation, consolidate subtitle file import under the subtitle menu.

Source checkpoints: iPad 4502474f32306d49b8a857ffabd90acb60c0a49e (seven watch-memory native tests passed; its first UI navigation test failed because it selected a TabBar absent on the tested iPad layout). Android 3aa16df42ed948f88137b2b928abee17be000c52 (CI 39789092945 passed). Both retain their independently verified 0.6.59/0.6.58 delivery ancestry. Private main remains older and is not overwritten.

Branches: feat/ipad-video-rotation-20261022 and feat/android-video-rotation-20261022. Version 0.6.61 build121. No server or router changes. No room protocol, transport, media URLs, seek, speed or audio modification.

Rotation advances 0,90,180,270,0 degrees clockwise. It only changes this device's rendering. Normal/fullscreen share rotation state. The view uses swapped fitting dimensions for odd quarter turns so the whole picture fits. iPad keeps the AVPlayer and caption/gesture layers outside the transform. Android keeps ExoPlayer/VLC instances and rotates their display children inside a dedicated rendering layout. Native text subtitles are moved to the stationary outer layer; external subtitle and control overlays remain stationary. Subtitles physically burned into a source, and native VLC composited bitmap output, rotate with that source image.

Subtitle import is now a subtitle-menu action. iPad dismisses the subtitle popover before opening the document picker and preserves cancellation handling. Android retains its already-existing subtitle-menu import action, removes the redundant fullscreen import tool and routes the chat tool through the subtitle menu. Existing subtitle adjustment remains available.

Validation workflow: native rotation geometry and memory tests, iPad real UI import/navigation/fullscreen checks, Android full unit tests plus memory persistence and actual decoded four-quadrant video rotation screenshot checks. APK/IPA publication is gated on passing the checks. Physical devices and two-device room playback remain unverified until installed.

Rollback: use the preceding platform installer without clearing application data. Watch memory lives in an independent archive and survives source deletion; uninstalling or clearing app data can erase it. No application data, deployed service or existing branch is deleted.
