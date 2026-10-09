StatikQuest @VERSION@ - Statik: Institute of Retention in VR, played on this PC and shown in
a headset: a Meta Quest through Virtual Desktop, or a PC headset through SteamVR or an
OpenXR runtime of its own. https://github.com/Jerware/StatikQuest

1. Put your own copy of the game in the games folder: its folder (the one with eboot.bin in
   it) or its .pkg file, which is unpacked the first time. Or skip this: a window asks where
   the game is. Keep this folder's path short, e.g. C:\Games\StatikQuest.
2. Virtual Desktop: install the Streamer on this PC and choose VDXR as the OpenXR runtime in
   its Options. For positional controller tracking, enable hand tracking on the headset
   and Virtual Desktop's "Forward tracking data to PC" feature.
   (With SteamVR instead: start it and see that the headset is ready.)
3. Connect the DualSense or DualShock 4 to this PC (USB cable, or Bluetooth paired with the
   PC, not with the headset), so the game receives its motion sensors and touchpad.
   Disable Steam Input if using a Steam shortcut.
4. Connect Virtual Desktop to this PC, then start "Play Statik VR.bat": its window has the
   game's language, field of view and desktop view to choose. Leave the defaults for your
   first run. If the Microsoft Visual C++ runtime is missing, the launcher says so.

Follow Statik's in-game prompts for the puzzle controls. Only the European base release,
CUSA06929, is supported. Most levels have been tested, but not all. There is no standalone
Quest app. Built-in JSON support is used; no separate decrypted JSON module is required.

Defaults are in pc-vr\settings.txt, personal settings in pc-vr\settings.local.txt, logs in
pc-vr\user\log, and saves in pc-vr\user\home. Keep your profile when updating; do not share
a used play folder, as it contains your saves and other private data.
Full installation and troubleshooting: https://github.com/Jerware/StatikQuest#readme

StatikQuest is free software under the GNU GPL, version 2 or later (LICENSE.txt); the source
is at the address above. It contains no part of the game: use it only with a game you own.
