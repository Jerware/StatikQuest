#!/usr/bin/env bash
# Packs the files of a GitHub release into build/release/:
#   AstroQuest-<version>-Quest3.apk           the headset app, build/quest/astro-vr-host.apk
#   AstroQuest-<version>-PC-VR-Windows.zip    the PC play folder: the emulator from
#                                             build/win-x64, the launcher, clean settings; no
#                                             game, saves, logs or caches
#   SHA256SUMS.txt
#   tools/make-release.sh <version>       (the version must be the APK's versionName)
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=${1:?usage: tools/make-release.sh <version>}
python=${PYTHON:-$(cat "$root/tools/python.local" 2>/dev/null || command -v python3 || command -v python)}
aapt2="${ANDROID_SDK:-$LOCALAPPDATA/Android/Sdk}/build-tools/36.1.0/aapt2.exe"
name="AstroQuest-$version"
out="$root/build/release"
pc="$out/$name-PC-VR-Windows"

apk="$root/build/quest/astro-vr-host.apk"
apk_version=$("$aapt2" dump badging "$apk" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")
[[ "$apk_version" == "$version" ]] || {
  echo "build/quest/astro-vr-host.apk is version $apk_version, not $version" >&2; exit 1; }

rm -rf "$out"
# The first user's home: without it the Windows build asks at its first start whether to move
# saves over from where an older shadPS4 kept them, in a message box behind the game.
mkdir -p "$pc/pc-vr/user/input_config" "$pc/games" \
         "$pc/pc-vr/user/home/1000/"{savedata,trophy,inputs}
cp "$apk" "$out/$name-Quest3.apk"

cp "$root/build/win-x64/shadps4.exe" "$pc/pc-vr/"
cp "$root/pc-vr/launch.ps1" "$pc/pc-vr/"
cp "$root/Play Astro Bot VR.bat" "$pc/"
cp "$root/pc-vr/user/input_config/default.ini" "$root/pc-vr/user/input_config/global.ini" \
   "$pc/pc-vr/user/input_config/"
# The settings file as documented: what the launcher's window saved here is left out.
sed '/^[a-z_]*=/d' "$root/pc-vr/settings.txt" > "$pc/pc-vr/settings.txt"
# The emulator's settings as the play folder has them, with everything that names this PC's
# folders or devices back at its default.
"$python" - "$(cygpath -m "$root/pc-vr/user/config.json")" \
    "$(cygpath -m "$pc/pc-vr/user/config.json")" <<'EOF'
import json, sys
config = json.load(open(sys.argv[1], encoding="utf-8"))
config["General"].update({"addon_install_dir": "", "font_dir": "", "home_dir": "",
                          "install_dirs": [], "sys_modules_dir": "", "shadnet_server": ""})
config["Input"].update({"default_controller_id": "", "camera_id": -1,
                        "motion_controls_enabled": True, "background_controller_input": True})
config["Vulkan"].update({"gpu_id": -1, "vkvalidation_enabled": False, "renderdoc_enabled": False})
config["Log"].update({"type": "file", "sync": False, "filter": "*:Info", "append": False})
for key in [k for k in config["Audio"] if k.endswith("_device")]:
    config["Audio"][key] = "Default Device"
json.dump(config, open(sys.argv[2], "w", encoding="utf-8"), indent=2)
EOF

cat > "$pc/games/PUT YOUR GAME HERE.txt" <<'EOF'
Put the folder of your own dump of ASTRO BOT Rescue Mission (European release CUSA12392,
version 1.00) in this folder, so that it holds CUSA12392\eboot.bin.

Or leave it where it is and name its eboot.bin in pc-vr\settings.txt:
game=D:\wherever\CUSA12392\eboot.bin

Either way, keep the path to the CUSA12392 folder under about 120 characters: some of the
game's files have long names, and the emulator cannot open a file whose full path is longer
than 260 characters.
EOF
cat > "$pc/README.txt" <<EOF
AstroQuest $version - ASTRO BOT Rescue Mission in VR, played on this PC and shown in a Meta
Quest through Virtual Desktop. https://github.com/bigmak94/AstroQuest

1. Put your own dump of the game in the games folder (see the note there). Keep this folder's
   path short, e.g. C:\Games\AstroQuest: the emulator cannot open the game's files whose full
   path would be longer than 260 characters.
2. Install the Microsoft Visual C++ Redistributable (x64) if the game does not start:
   https://aka.ms/vs/17/release/vc_redist.x64.exe
3. Virtual Desktop: install the Streamer on this PC and choose VDXR as the OpenXR runtime in
   its Options. In the headset, set Virtual Desktop's frame rate to 120 (Streaming settings).
4. Connect the DualSense to this PC (USB cable, or Bluetooth paired with the PC, not with the
   headset). Without a gamepad the headset's Touch controllers play.
5. Connect Virtual Desktop to this PC, then start "Play Astro Bot VR.bat".

In the game: hold the controller where the outline is on the first screen; look at a planet
and press X to choose it; hold OPTIONS for a second to reset the view. Settings are in
pc-vr\settings.txt, the log in pc-vr\user\log\shad_log.txt, saves in pc-vr\user\home.

AstroQuest is free software under the GNU GPL, version 2 or later (LICENSE.txt); the source is
at the address above. It contains no part of the game: use it only with a game you own.
EOF
tr -d '\r' < "$root/LICENSE" > "$pc/LICENSE.txt"
cp "$root/THIRD-PARTY-NOTICES.md" "$pc/THIRD-PARTY-NOTICES.md"

"$python" - "$(cygpath -m "$out")" "$name-PC-VR-Windows" <<'EOF'
import os, sys, zipfile
out, folder = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(os.path.join(out, folder + ".zip"), "w", zipfile.ZIP_DEFLATED,
                     compresslevel=9) as archive:
    for here, folders, files in sorted(os.walk(os.path.join(out, folder))):
        if not folders and not files:
            archive.write(here, os.path.relpath(here, out).replace(os.sep, "/") + "/")
        for name in sorted(files):
            path = os.path.join(here, name)
            archive.write(path, os.path.relpath(path, out).replace(os.sep, "/"))
EOF
(cd "$out" && sha256sum "$name-Quest3.apk" "$name-PC-VR-Windows.zip" > SHA256SUMS.txt)
ls -la "$out"
cat "$out/SHA256SUMS.txt"
