#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Exercise real first-use bundled installation: no model preloading or network fetch.
# Volume restoration is a timed animation; keep animator timing enabled even
# when emulator window/transition animations are disabled for UI stability.
adb shell settings put global animator_duration_scale 1
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
bash android/ui-check.sh
