# Statik on PC VR

Start **Play Statik VR.bat** at the repository or PC package root. Its Windows
settings window follows AstroQuest's layout, adapted exclusively for Statik.

## Headset setup

For a Quest, connect Virtual Desktop to this PC and use VDXR as its OpenXR
runtime. For an Index or another SteamVR headset, start SteamVR and select it as
your OpenXR runtime. Other PC OpenXR runtimes use the same path. The launcher
does not change system/runtime settings. There is no standalone Quest app.

Statik's rendering cadence is game-controlled. A desktop startup check is not
physical-headset verification.

Connect your DualSense/DualShock to the PC itself, not the headset, so the
emulator receives its motion sensors and touchpad. Disable Steam Input for any
Steam shortcut. Where supported, Virtual Desktop can forward hand tracking to
place the gamepad; without tracked position, shared VR code provides a fixed
position. VR-controller replacement, positional tracking, recenter shortcuts
and puzzle interactions still need verification in Statik.

## Game

Use the CUSA06929 European **base game**: its extracted `eboot.bin`, its folder,
or a compatible unencrypted `.pkg`. Other games/regions and update-only packages
are rejected. PkgTool is required only for package extraction; `.iso` files are
not supported by the launcher.

If no game is found, the launcher shows **Where is the game?** Choose **Show
where it is...** to select `eboot.bin` or a `.pkg`, or place your copy in the
`games` folder and choose **Look again**. Once a game is found, this setup window
is skipped on subsequent starts, following AstroQuest's flow.

The extractor uses a separate temporary folder and validates the game's metadata
before installation. It never overwrites an existing installation. Failure or
cancellation retains partial files/logs, and the original package is kept. Keep
installation paths short.

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

Most levels have been tested, but not all. The current build has passed a headset
play test; full-game completion and broad hardware compatibility remain unverified.

When testing your setup, check stereo depth/eye alignment, head and controller
tracking, recentering, pause/menu overlays and effects in both eyes, sound, a
level transition, save/load and normal exit. Logs are in `pc-vr/user/log`; check
for private paths before sharing them, and never include games, modules or saves.
