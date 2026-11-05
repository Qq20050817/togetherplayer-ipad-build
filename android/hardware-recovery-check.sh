#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 android/emulator-preflight.py
adb shell settings put global animator_duration_scale 1
adb shell svc power stayon true
adb shell settings put system screen_off_timeout 1800000
adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard
adb shell am force-stop com.android.launcher3
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
evidence="$PWD/android-delivery/native-evidence"
mkdir -p "$evidence"
run_check() {
 local label="$1" classes="$2" result=0
 gradle -p android --no-daemon connectedDebugAndroidTest "-Pandroid.testInstrumentationRunnerArguments.class=$classes" || result=$?
 mkdir -p "$evidence/$label"
 cp -a android/app/build/outputs/androidTest-results/. "$evidence/$label/"
 mkdir -p android-delivery/screenshots
 adb pull /sdcard/Pictures/TogetherUITests/ android-delivery/screenshots/ || true
 test "$result" -eq 0
}
run_check targeted-15 dev.together.poc.HevcHdrCapabilityTest,dev.together.poc.Main10DecoderTest,dev.together.poc.LocalDocumentPlaybackTest,dev.together.poc.CompatiblePlaybackTest,dev.together.poc.CompatibleHttpRecoveryTest,dev.together.poc.EmbeddedSubtitleTest
# The original failure was intermittent after output transitions. Repeat only
# that real 24fps Main10 chroma/motion/audio/rate/seek case, retaining each XML.
run_check movie-rate-repeat-1 dev.together.poc.CompatiblePlaybackTest#main10MovieRateHttpKeepsColorsAudioAndPositionDuringCatchup
run_check movie-rate-repeat-2 dev.together.poc.CompatiblePlaybackTest#main10MovieRateHttpKeepsColorsAudioAndPositionDuringCatchup
