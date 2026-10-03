#!/usr/bin/env bash
# The game's save is the same on the headset's own app and on the PC build: this copies the
# headset's to the PC, so that what was played there goes on here. The headset has to be on
# the cable; nothing on it is changed. A save the PC build already has is kept next to the new
# one.
#
#   tools/quest-save-to-pc.sh
set -u
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
export ANDROID_SERIAL=${ANDROID_SERIAL:-$(cat "$(dirname "${BASH_SOURCE[0]}")/quest-serial.local" 2>/dev/null)}
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
package=com.astrobotquest.vrhost
remote=/sdcard/Android/data/$package/files/data/shadPS4/home/1000/savedata/CUSA12392
local_dir="$root/pc-vr/user/home/1000/savedata/CUSA12392"
stamp=$(date +%Y%m%d-%H%M%S)

if ! "$ADB" get-state > /dev/null 2>&1; then
    echo "the headset is not connected (adb sees no device $ANDROID_SERIAL)"
    exit 1
fi

files=$("$ADB" shell "cd $remote 2>/dev/null && find . -type f" | tr -d '\r')
if [ -z "$files" ]; then
    echo "the headset's app has no save ($remote)"
    exit 1
fi
if [ -d "$local_dir" ]; then
    mv "$local_dir" "$local_dir.before-$stamp"
    echo "the PC's own save was kept as $(basename "$local_dir.before-$stamp")"
fi
for file in $files; do
    file=${file#./}
    mkdir -p "$local_dir/$(dirname "$file")"
    # (Not "adb pull": with path conversion off, adb.exe is given a path it cannot write to.)
    "$ADB" exec-out "cat $remote/$file" > "$local_dir/$file"
done
echo "the headset's save is in $local_dir:"
find "$local_dir" -type f -exec ls -la {} +
