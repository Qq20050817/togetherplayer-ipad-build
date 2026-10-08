# Android decoder sources

TogetherPlayer Android 0.4.0 includes Jellyfin's GPL-3.0 Media3 FFmpeg audio
decoder 1.6.1+2, compiled for Media3 1.7.1. Distribution of the combined Android
application follows GPL-3.0; the full Android application source and build files
are included with this release's source delivery. Existing third-party notices
continue to apply. The GPL text is bundled in the APK assets.

Upstream corresponding sources and build recipe:
https://github.com/jellyfin/jellyfin-androidx-media/tree/v1.6.1%2B2
Use its pinned `media` and `ffmpeg` submodules, not their current main branches.
The published coordinate is org.jellyfin.media3:media3-ffmpeg-decoder:1.6.1+2.
The upstream build.sh enables dca, truehd, mlp, ac3, eac3, aac, mp3, flac and
alac. It produces PCM audio; this does not preserve TrueHD Atmos objects.

Build TogetherPlayer with Java 17, Android SDK 35 and Gradle 8.9:
`gradle --no-daemon testDebugUnitTest assembleDebug assembleDebugAndroidTest`.
The audio decoder does not add software HEVC video decoding. Video capability
still depends on system codecs; codec initialization fallback is enabled.
