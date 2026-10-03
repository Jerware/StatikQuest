#!/usr/bin/env bash
# Runs the ARM64 core on a connected Quest straight from adb shell, without the VR host app:
# no display, scripted controller input, a screenshot every N presented frames. This checks the
# core on the real CPU and GPU even while the headset is locked or not being worn.
#
#   tools/quest-core-test.sh <seconds> [input script] [screenshot interval] [NAME=value ...]
#
# Needs the runtime in /data/local/tmp/astro/runtime and the game in
# /data/local/tmp/astro/games/CUSA12392 on the device. Results land in build/quest/run/.
set -u
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
# The headset also shows up over the network: name the USB connection.
export ANDROID_SERIAL=${ANDROID_SERIAL:-$(cat "$(dirname "${BASH_SOURCE[0]}")/quest-serial.local" 2>/dev/null)}
device=/data/local/tmp/astro
# ASTRO_DRIVER picks another Vulkan driver folder on the device (default: the packaged Turnip).
driver=${ASTRO_DRIVER:-$device/runtime/drivers/turnip}

seconds=${1:-60}
script=${2:-}
shots=${3:-600}
shift $(( $# < 3 ? $# : 3 ))
extra_env="$*"

cd "$root" || exit 1
mkdir -p build/quest/run
tools/llvm/bin/llvm-strip.exe -o build/quest/shadps4-stripped build/arm64/shadps4 || exit 1
"$ADB" push build/quest/shadps4-stripped $device/runtime/host/shadps4-arm64-fex | tail -1

user=$device/home/data/shadPS4
"$ADB" shell "mkdir -p $user $device/home/cache $device/tmp && chmod 755 $device/runtime/host/shadps4-arm64-fex \
  && rm -rf $user/screenshots && echo $shots > $user/auto_shot_every && rm -f $device/core.log $device/input.txt"
input_env=""
if [[ -n "$script" ]]; then
  "$ADB" push "$script" $device/input.txt | tail -1
  input_env="SHADPS4_INPUT_SCRIPT=$device/input.txt"
fi

"$ADB" shell "cd $device && env HOME=$device/home XDG_DATA_HOME=$device/home/data XDG_CACHE_HOME=$device/home/cache \
  XDG_CONFIG_HOME=$device/home/config TMPDIR=$device/tmp MESA_SHADER_CACHE_DIR=$device/home/cache/mesa \
  GLIBC_TUNABLES=glibc.pthread.rseq=0 LD_LIBRARY_PATH=$device/runtime/host:$driver \
  VK_ICD_FILENAMES=$driver/freedreno_icd.aarch64.json \
  SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy SHADPS4_HEADLESS=1 $input_env $extra_env \
  timeout $seconds ./runtime/host/ld-linux-aarch64.so.1 --library-path $device/runtime/host:$driver \
  ./runtime/host/shadps4-arm64-fex -g $device/games/CUSA12392/eboot.bin > core.log 2>&1; echo exit=\$? >> core.log"

rm -rf build/quest/run/screenshots
"$ADB" pull $device/core.log build/quest/run/core.log | tail -1
"$ADB" pull $user/screenshots build/quest/run/ 2>&1 | tail -1
"$ADB" pull $user/log build/quest/run/ 2>&1 | tail -1
tail -1 build/quest/run/core.log
