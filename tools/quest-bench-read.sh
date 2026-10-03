#!/usr/bin/env bash
# Sums up a run of tools/quest-level-bench.sh: tools/quest-bench-read.sh <name> [all]
# Frames a second by ten seconds, for how many refreshes frames were shown, what the governor
# decided, and every ten seconds what frames took, at what size, with the GPU how busy.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out="$root/build/quest/bench"
name=$1
echo "fps by 10 s: $(grep -a -E "^[0-9]+ s:" "$out/$name.txt" | sed -E 's/.*frames, ([0-9.]+) per second.*/\1/' | tr '\n' ' ')"
echo "shown for 1-2-3-more refreshes: $(grep -a -E "shown for" "$out/$name.txt" | sed -E 's/ *frames shown for one refresh: ([0-9]+), for two: ([0-9]+), for three: ([0-9]+), for more: ([0-9]+)/\1-\2-\3-\4/' | tr '\n' ' ')"
echo "GPU clock by 10 s (busy% MHz C): $(awk 'NR%10==1 {printf "%s/%s/%s ", $2, $3, $4}' "$out/$name.gpu.txt")"
pattern="scene is drawn at|Frames are given|title's clock"
[ "${2:-}" = all ] && pattern="$pattern|frame stats at|frame path"
sed -e 's/\x1b\[[0-9;]*m//g' "$out/$name.core.log" | grep -a -E "$pattern" \
  | sed -E 's/^\[[A-Za-z.]+\] <Info> \([A-Za-z:]+\) [a-z_]+\.cpp:[0-9]+ [A-Za-z]+: //' \
  | sed -E 's/, per frame [0-9.]+ passes \([^)]*\)//; s/, [0-9.]+ dispatches.*//; s/The title.s clock: //; s/, the game ran at ([0-9]+)% of its speed over the last [0-9]+ s \(it would have at [0-9]+% left to itself\)/ (\1% speed)/' \
  | cut -c1-240
