#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-false}" = true ]; then
  adb shell am force-stop com.android.launcher3
  adb shell input keyevent KEYCODE_WAKEUP
  adb shell wm dismiss-keyguard
  adb install -r android/app/build/outputs/apk/debug/app-debug.apk
  result=0
  gradle -p android --no-daemon connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=dev.together.poc.EmbeddedSubtitleTest || result=$?
  mkdir -p android-delivery/screenshots
  adb pull /sdcard/Pictures/TogetherUITests/ android-delivery/screenshots/ || true
  exit "$result"
else
  bash android/voice-ui-check.sh
fi
