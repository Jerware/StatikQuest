#!/usr/bin/env bash
# Runs the app's self-test into the first level of the game (it starts from a save, past the
# prologue: the test's own data folder bench-data in the app's files folder, made once from the
# sandbox tests' save) with a stand-in for the compositor and a display loop, and keeps the
# report, the logs and the GPU's clock under build/quest/bench/<name>.*:
#
#   tools/quest-level-bench.sh <name> <seconds> [NAME=value ...]
#
# BENCH_HZ=<rate> in the environment sets the refresh rate of the stand-in display, of the
# stand-in compositor and of the emulated headset (90 unless told). They are not to be given
# among the settings as well: the self-test does not take a setting of its own twice.
#
# The head looks at the level's first planet until the level is in (85 degrees left, 22 up),
# then down the level from second 110 on, which is its heaviest view. Prints a summary.
set -u
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
name=$1
seconds=$2
shift 2
out="$root/build/quest/bench"
data=/data/user/0/com.astrobotquest.vrhost/files/bench-data
hz=${BENCH_HZ:-90}
mkdir -p "$out"
rm -f "$out/$name.done"
bash "$root/tools/quest-gpu-watch.sh" $((seconds + 15)) "$out/$name.gpu.txt" &
bash "$root/tools/quest-selftest.sh" "$seconds" "HOST_LOOK=8:85,22;110:0,-12" "HOST_DISPLAY=$hz" \
  "HOST_COMPOSITOR=$hz" "SHADPS4_VR_REFRESH_RATE=$hz" "XDG_DATA_HOME=$data" "$@" \
  > "$out/$name.txt" 2>&1
cp "$root/build/quest/selftest/core.log" "$out/$name.core.log" 2>/dev/null
cp "$root/build/quest/selftest/host.log" "$out/$name.host.log" 2>/dev/null
wait
echo done > "$out/$name.done"
bash "$root/tools/quest-bench-read.sh" "$name"
