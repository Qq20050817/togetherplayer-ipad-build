#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Exercise real first-use bundled installation: no model preloading or network fetch.
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
bash android/ui-check.sh
