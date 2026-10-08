#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
curl -fL --retry 2 --max-time 120 https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip -o /tmp/voice-cn.zip
echo '3af8b0e7e0f835ae9d414ce5df580237a3cfb08d586c9fbbb0f7ff29ad5b14ba  /tmp/voice-cn.zip' | sha256sum -c -
mkdir -p /tmp/voice-model-cn
unzip -q /tmp/voice-cn.zip -d /tmp/voice-model-cn
printf '%s' 3af8b0e7e0f835ae9d414ce5df580237a3cfb08d586c9fbbb0f7ff29ad5b14ba > /tmp/voice-model-cn/.verified
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb push /tmp/voice-model-cn /data/local/tmp/voice-model-cn
adb shell chmod -R a+rX /data/local/tmp/voice-model-cn
adb shell run-as dev.together.poc mkdir -p files
adb shell run-as dev.together.poc cp -R /data/local/tmp/voice-model-cn files/voice-model-cn
bash android/ui-check.sh
