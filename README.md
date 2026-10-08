> [!WARNING]
> # 🚧 UNDER CONSTRUCTION 🚧
> This project is under active development and is not yet ready for general use.

# StatikQuest

Statik: Institute of Retention (PS4 / PlayStation VR), played on a Windows PC
through a PS4 emulator and shown in a headset through OpenXR. Based on
[AstroQuest](https://github.com/bigmak94/AstroQuest) and
[shadPS4](https://github.com/shadps4-emu/shadPS4).

This is a **Statik-only PC VR fork**. Quest headsets work through a PC connection
such as Virtual Desktop or SteamVR; there is no standalone Quest app or APK build.

No game, firmware, system modules, keys or proprietary SDK files are included.
Bring your own game dump and compatible decrypted `libSceJson2.sprx` module.

## Status

The Statik compatibility work was ported onto the newer AstroQuest fork. The
Release build and quick regression checks passed; desktop preview reached Statik's
start screen in both eyes. Full headset acceptance testing remains pending.

Support is currently for the European base game, **CUSA06929**. Other regions and
updates have not been verified. The launcher rejects other games and update-only
packages; it does not launch Astro Bot.

## Playing on PC VR

1. Connect your headset through Virtual Desktop or start its OpenXR runtime
   (SteamVR for headsets that use it). The launcher uses the active runtime
   without changing it.
2. Connect a DualSense/DualShock to the PC itself by USB or Bluetooth. Disable
   Steam Input if launching from a Steam shortcut.
3. Start **Play Statik VR.bat**. Put your own extracted game in `games`, or
   select its `eboot.bin` when asked. PkgTool can unpack a compatible unencrypted
   base-game `.pkg`, keeping the original and protecting existing installations.
4. Select your compatible decrypted `libSceJson2.sprx` when asked. A private copy
   is kept in `pc-vr/user/custom_modules/CUSA06929`.
5. Choose console language, field of view and desktop view, then press Play.
   Follow Statik's in-game prompts for the puzzle controls.

The launcher retains AstroQuest's Windows interface, adapted for Statik. Its
Astro Bot-specific resolution and maximum-frame-rate controls are removed:
Statik controls its own rendering size and cadence. Shared VR/input features
still need verification in Statik. See [the PC VR guide](README-PC-VR.md).

## Repository layout

- `pc-vr/`: launcher, default settings and package validation. Generated emulator,
  personal settings, private modules and saves are ignored.
- `shadps4-arm64-main/`: inherited emulator source and pinned dependencies.
  Its upstream folder name is retained; it does not imply a standalone Quest app.
- `tools/`: build/staging scripts, developer tools and regression tests.
- `build/`: ignored local build output.

Standalone-Quest and separate beta-release preparation files are no longer in
the active project. Previous versions remain recoverable from Git history.

## Building from source

On Windows, use Visual Studio C++ Build Tools with a Windows SDK, CMake/Ninja,
Git and LLVM (`clang-cl`, `llvm-lib`, `llvm-rc`). LLVM 21.1.8 was used locally.
No Sony SDK is required.

```powershell
git submodule update --init --recursive
.\tools\build_pcvr_release.ps1 -LlvmDirectory C:\path\to\llvm\bin
.\tools\test_pcvr_release.ps1 -LlvmDirectory C:\path\to\llvm\bin -BuildDirectory .\build\pcvr_release
.\tools\make-pc-vr.ps1 -PkgToolDirectory C:\path\to\pkgtool
```

PkgTool/LibOrbisPkg v0.2.231 is optional for already extracted games. Staging
updates the playable emulator without overwriting an existing profile or copying
games, modules or saves from another workspace. `tools/make-pc-vr.sh` is the
equivalent Git Bash entry point.

`tools/make-release.sh <version>` makes a clean, PC-only local staging archive.
It does not upload a release or establish distribution/license clearance.

## License and credits

StatikQuest is GPL-2.0-or-later; see [LICENSE](LICENSE) and
[third-party notices](THIRD-PARTY-NOTICES.md). Inherited release-audit concerns,
including FDK-AAC compatibility and static dependency source/relinking obligations,
remain unresolved. Local build checks are not public-release clearance.

Thanks to bigmak94/AstroQuest, the shadPS4 and shadps4-arm64 contributors, and the
OpenXR/Vulkan and third-party library authors. Original ownership and license
notices remain in the source. This project is not affiliated with or endorsed by
the game's publisher, Sony, Meta or headset vendors.
