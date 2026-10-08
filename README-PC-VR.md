# Statik on PC VR

Start **Play Statik VR.bat** at the repository or PC package root. Its Windows
settings window follows AstroQuest's layout, adapted exclusively for Statik.

## Headset setup

For a Quest, connect Virtual Desktop to this PC and use VDXR as its OpenXR
runtime. For an Index or another SteamVR headset, start SteamVR and select it as
your OpenXR runtime. Other PC OpenXR runtimes use the same path. The launcher
does not change system/runtime settings. There is no standalone Quest app.

Start with a headset refresh rate of 120 Hz; Statik's rendering cadence is
game-controlled. A desktop startup check is not physical-headset verification.

Connect your DualSense/DualShock to the PC itself, not the headset, so the
emulator receives its motion sensors and touchpad. Disable Steam Input for any
Steam shortcut. Where supported, Virtual Desktop can forward hand tracking to
place the gamepad; without tracked position, shared VR code provides a fixed
position. VR-controller replacement, positional tracking, recenter shortcuts
and puzzle interactions still need verification in Statik.

## Game and module

Use the CUSA06929 European **base game**: its extracted `eboot.bin`, its folder,
or a compatible unencrypted `.pkg`. Other games/regions and update-only packages
are rejected. PkgTool is required only for package extraction.

The extractor uses a separate temporary folder and validates the game's metadata
before installation. It never overwrites an existing installation. Failure or
cancellation retains partial files/logs, and the original package is kept. Keep
installation paths short.

Statik also needs your own compatible decrypted `libSceJson2.sprx`. If missing,
the launcher asks for it, checks its ELF header and keeps a private copy in
`pc-vr/user/custom_modules/CUSA06929`. Do not upload your game or module.

## Launcher settings

- **Console language**: Windows' language or a selected console language.
  Availability depends on your copy of the game.
- **Field of view**: 70–100 percent. PSVR is the conservative default;
  `fov_of=headset` uses the headset's reported view. Test eye alignment.
- **Desktop view**: stereo, single-eye spectator or combined-eye spectator,
  optionally cropping top/bottom to fill the window.
- **Show this window at every start**: untick to skip the menu next time.

There is no resolution slider or maximum-frame-rate selector. Those upstream
controls patched Astro Bot and cannot override Statik. Old `resolution`, `fps`,
`dynamic`, `pace` and `real_time` settings are not applied.

Defaults are in `pc-vr/settings.txt`; your choices and game path are saved in
ignored `pc-vr/settings.local.txt`, leaving the tracked template unchanged.
Advanced shared tracking/sharpening/pause settings are in that template.
`headset=0` provides desktop preview with synthetic tracking, not a headset test.

## Saves and testing

The playable emulator is `pc-vr/shadps4.exe`; its profile, logs and caches are
under `pc-vr/user`, with saves under `user/home`. Updating the executable preserves
the profile. Used play folders contain private data: do not upload them as a
release package.

The old AstroQuest development folder and its original launchers were not changed.

For headset acceptance, check stereo depth/eye alignment, head and controller
tracking, recentering, pause/menu overlays and effects in both eyes, sound, a
level transition, save/load and normal exit. Logs are in `pc-vr/user/log`; check
for private paths before sharing them, and never include games, modules or saves.
