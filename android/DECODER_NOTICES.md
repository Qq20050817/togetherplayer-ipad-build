# Android decoder sources

TogetherPlayer Android 0.5.8 includes Jellyfin's GPL-3.0 Media3 FFmpeg audio
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
The Jellyfin extension provides audio decoding only. Version 0.5.8 adds a separate
LibVLC 3.6.5 video path for local HEVC Main10 runtime failures. LibVLC is unmodified
and uses its avcodec software video decoder; the normal path remains Media3.
LibVLC Android source and build recipe: https://code.videolan.org/videolan/vlc-android
VLC engine sources: https://code.videolan.org/videolan/vlc
Published binary and Java sources: https://repo.maven.apache.org/maven2/org/videolan/android/libvlc-all/3.6.5/
LibVLC license: LGPL-2.1-or-later, included in assets/LGPL-2.1-LibVLC.txt.
The complete application source remains available for rebuilding with a replaced library.

ARM64 delivery: `gradle -p android assembleDebug -PdeliveryArm64=true`.
Native emulator checks use the regular multi-ABI build.
