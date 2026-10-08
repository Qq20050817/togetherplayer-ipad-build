#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
mkdir -p ../android-delivery/screenshots
adb shell svc power stayon true
adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard
# A Quickstep ANR dialog can steal every test window focus on a fresh emulator.
adb shell am force-stop com.android.launcher3
adb shell settings put system screen_off_timeout 1800000
check_result=0
gradle --no-daemon connectedDebugAndroidTest || check_result=$?
for name in 01-portrait 02-room-settings 03-landscape 04-fullscreen-controls 05-fullscreen-hidden; do
  adb pull /sdcard/Pictures/TogetherUITests/$name.png ../android-delivery/screenshots/$name.png || true
done
if [ "$check_result" -ne 0 ]; then
  adb shell screencap -p /sdcard/together-ui-failure.png
  adb pull /sdcard/together-ui-failure.png ../android-delivery/screenshots/06-failure-screen.png || true
fi
exit "$check_result"
