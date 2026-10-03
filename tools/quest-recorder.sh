#!/usr/bin/env bash
# The headset is played without a cable, so what a session looked like to the system has to be
# written down on the headset itself. This keeps a small recorder running there (see
# tools/quest-recorder-device.sh for what it keeps) and fetches what it and the app recorded.
#
#   tools/quest-recorder.sh start    put the recorder on the headset and start it (it stays
#                                    until the headset restarts; starting it twice is harmless)
#   tools/quest-recorder.sh status   whether it runs, and the sessions it has
#   tools/quest-recorder.sh pull     fetch everything to build/quest/sessions/<start time>/,
#                                    with the app's host.log and core.log next to the newest
#   tools/quest-recorder.sh stop
set -u
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
export ANDROID_SERIAL=${ANDROID_SERIAL:-$(cat "$(dirname "${BASH_SOURCE[0]}")/quest-serial.local" 2>/dev/null)}
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
stage=/data/local/tmp/astro
package=com.astrobotquest.vrhost

running() {
  "$ADB" shell "pid=\$(cat $stage/recorder.pid 2>/dev/null); [ -n \"\$pid\" ] && grep -q recorder /proc/\$pid/cmdline 2>/dev/null && echo \$pid" | tr -d '\r'
}

case "${1:-status}" in
start)
  if [ -n "$(running)" ]; then
    echo "the recorder already runs (process $(running))"
    exit 0
  fi
  # (A relative path: with path conversion off, adb.exe does not know what /c/... is.)
  cd "$root" || exit 1
  "$ADB" push tools/quest-recorder-device.sh $stage/recorder.sh > /dev/null || exit 1
  # Its own session and no terminal: it has to outlive this connection and the cable.
  "$ADB" shell "setsid sh $stage/recorder.sh < /dev/null > /dev/null 2>&1 &"
  sleep 2
  if [ -n "$(running)" ]; then
    echo "the recorder runs (process $(running))"
  else
    echo "the recorder did not start"
    exit 1
  fi
  ;;
stop)
  pid=$(running)
  if [ -n "$pid" ]; then
    # Its children (the log reader of a session under way) go with it.
    "$ADB" shell "pkill -P $pid; kill $pid"
    echo "stopped"
  else
    echo "it was not running"
  fi
  ;;
status)
  pid=$(running)
  echo "recorder: ${pid:+runs as process }${pid:-not running}"
  "$ADB" shell "cd $stage/sessions 2>/dev/null && for s in *; do [ -d \$s ] && echo \"\$s: \$(wc -l < \$s/gpu.txt 2>/dev/null) samples, \$(grep -c FPS= \$s/system.txt 2>/dev/null) runtime lines\"; done; true"
  ;;
pull)
  out="$root/build/quest/sessions"
  mkdir -p "$out"
  names=$("$ADB" shell "ls $stage/sessions 2>/dev/null" | tr -d '\r')
  newest=""
  for name in $names; do
    mkdir -p "$out/$name"
    for file in gpu.txt system.txt threads.txt; do
      # (Not "adb pull": with path conversion off, adb.exe is given a path it cannot write to.)
      "$ADB" exec-out "cat $stage/sessions/$name/$file 2>/dev/null" > "$out/$name/$file"
    done
    newest=$name
  done
  # The app's own logs are of its last two starts.
  files=/sdcard/Android/data/$package/files
  target="$out/${newest:-app}"
  mkdir -p "$target"
  for file in host.log core.log host.prev.log core.prev.log; do
    "$ADB" exec-out "cat $files/$file 2>/dev/null" > "$target/$file"
  done
  echo "sessions: ${names:-none}"
  ls -la "$target"
  ;;
*)
  echo "usage: $0 start|status|pull|stop"
  exit 64
  ;;
esac
