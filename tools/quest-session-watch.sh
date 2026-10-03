#!/usr/bin/env bash
# Records what a real session of the app looks like from the outside, on a Quest connected by
# USB: waits for the app to be started in the headset, then, until it ends, keeps
#
#   session/logcat.txt   the app's log and the VR runtime's own lines about it (frame timing,
#                        processor and GPU levels) as they are written
#   session/gpu.txt      every five seconds: seconds, GPU load %, GPU clock MHz, GPU temperature,
#                        clock of every processor core in MHz
#   session/threads.txt  every thirty seconds: the emulator's busiest threads and the cores
#                        they last ran on
#
# and afterwards pulls the app's host.log and core.log next to them. All of it is in
# build/quest/session/. The app cannot read the GPU's state itself, a shell can.
#
#   tools/quest-session-watch.sh [seconds to wait for the app, default 7000]
#
# Nothing on the headset is changed. Stop it with Ctrl+C at any time.
set -u
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
export ANDROID_SERIAL=${ANDROID_SERIAL:-$(cat "$(dirname "${BASH_SOURCE[0]}")/quest-serial.local" 2>/dev/null)}
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
package=com.astrobotquest.vrhost
wait_seconds=${1:-7000}
out="$root/build/quest/session"

app_pid() {
  "$ADB" shell "pidof $package" 2>/dev/null | tr -d '\r'
}

echo "waiting up to $wait_seconds s for $package to start"
waited=0
while [ -z "$(app_pid)" ]; do
  if [ "$waited" -ge "$wait_seconds" ]; then
    echo "the app was not started"
    exit 3
  fi
  sleep 5
  waited=$((waited + 5))
done
echo "the app runs (after $waited s)"

rm -rf "$out"
mkdir -p "$out"
# Only what is logged from now on; the log already on the headset is left alone.
"$ADB" logcat -T 1 -v time AstroVR:V VrApi:V crcs:V OpenXR:I ActivityManager:I AAudio:W '*:S' \
  > "$out/logcat.txt" 2>&1 &
logcat_pid=$!

"$ADB" shell 'start=$(date +%s); while pidof '"$package"' > /dev/null; do
  echo "$(( $(date +%s) - start )) $(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage | tr -d " %") $(( $(cat /sys/class/kgsl/kgsl-3d0/gpuclk) / 1000000 )) $(( $(cat /sys/class/kgsl/kgsl-3d0/temp) / 1000 )) $(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq | while read f; do printf "%s " $(( f / 1000 )); done)"
  sleep 5; done' > "$out/gpu.txt" 2>&1 &
gpu_pid=$!

"$ADB" shell 'start=$(date +%s); while pidof '"$package"' > /dev/null; do
  core=$(pidof libastro_ld.so)
  if [ -n "$core" ]; then
    echo "== $(( $(date +%s) - start )) s"
    top -H -b -n 1 -m 24 -o PID,TID,%CPU,S,PR,NI,CMD,PCY,CPU -p $core 2>&1 | tail -n +6
    echo "cpus allowed: $(grep Cpus_allowed_list /proc/$core/status | cut -f2), cpuset $(cat /proc/$core/cpuset)"
  fi
  sleep 30; done' > "$out/threads.txt" 2>&1 &
threads_pid=$!

# Until the app is gone (or this is interrupted).
trap 'kill $logcat_pid $gpu_pid $threads_pid 2>/dev/null' EXIT
while [ -n "$(app_pid)" ]; do
  sleep 5
done
echo "the app ended"
sleep 2
kill $logcat_pid 2>/dev/null

files=/sdcard/Android/data/$package/files
for name in host.log core.log; do
  # (Not "adb pull": with path conversion off, adb.exe is given a path it cannot write to.)
  "$ADB" exec-out "cat $files/$name" > "$out/$name" 2>/dev/null
  [ -s "$out/$name" ] || echo "no $name"
done
ls -la "$out"
grep -a "pacing:\|hands:\|microphone\|session state\|refresh rate\|performance" "$out/host.log" 2>/dev/null | tail -40
