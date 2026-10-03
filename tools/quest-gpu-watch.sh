#!/usr/bin/env bash
# Writes how busy the headset's GPU is and how fast it is clocked, once a second, for so many
# seconds: tools/quest-gpu-watch.sh <seconds> <file>. One line per sample:
#   seconds  busy%  GPU MHz  GPU temperature
# The shell may read that while the headset sleeps; the app may not.
ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
export ANDROID_SERIAL=${ANDROID_SERIAL:-$(cat "$(dirname "${BASH_SOURCE[0]}")/quest-serial.local" 2>/dev/null)} MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
"$ADB" shell "start=\$(date +%s); while [ \$(( \$(date +%s) - start )) -lt $1 ]; do
  echo \"\$(( \$(date +%s) - start )) \$(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage | tr -d ' %') \$(( \$(cat /sys/class/kgsl/kgsl-3d0/gpuclk) / 1000000 )) \$(( \$(cat /sys/class/kgsl/kgsl-3d0/temp) / 1000 ))\"
  sleep 1; done" > "$2" 2>&1
