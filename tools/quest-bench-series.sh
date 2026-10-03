#!/usr/bin/env bash
# Runs the self-test several times in a row with different settings and keeps each run's
# report and logs under build/quest/bench/<name>.*, for comparing what a setting costs.
#
#   tools/quest-bench-series.sh <seconds> <common settings> -- <name>:<settings> [<name>:<settings> ...]
#
# Settings are what tools/quest-selftest.sh takes (NAME=value, separated by spaces; quote
# each group). Example:
#   tools/quest-bench-series.sh 185 "HOST_LOOK=8:85,22;115:0,-12 HOST_COMPOSITOR=90" -- \
#       "plain:SHADPS4_MAX_MSAA=1" "msaa2:SHADPS4_MAX_MSAA=2"
set -u
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
seconds=$1
common=$2
shift 3
out="$root/build/quest/bench"
mkdir -p "$out"
for run in "$@"; do
  name=${run%%:*}
  settings=${run#*:}
  rm -f "$out/$name.done"
  # shellcheck disable=SC2086
  bash "$root/tools/quest-selftest.sh" "$seconds" $common $settings > "$out/$name.txt" 2>&1
  cp "$root/build/quest/selftest/core.log" "$out/$name.core.log" 2>/dev/null
  cp "$root/build/quest/selftest/host.log" "$out/$name.host.log" 2>/dev/null
  echo done > "$out/$name.done"
done
echo done > "$out/series.done"
