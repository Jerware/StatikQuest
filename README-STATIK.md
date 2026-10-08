# StatikQuest development guide

StatikQuest ports the Statik compatibility work from AstroQuest commit
`9f42c44d4e838e3a0df67913e350c4f098110862` onto the newer AstroQuest code through
`807ca1f3777d4cea30f78713dedf6d70d69b51db` (0.20). The local `statik-support`
branch retains that newer history and the UNDER CONSTRUCTION notice.

## Scope

Windows x64 / PC VR only. The launcher currently accepts the European base game,
**CUSA06929**. Other game regions and updates have not been verified. Supply your
own extracted game (select `eboot.bin`) and compatible decrypted
`libSceJson2.sprx`. No game or system modules are distributed.

The port includes the older tracker initialization layout, packed stereo eye
textures, per-eye pause/UI overlays, ongoing reprojection of the last frame,
ctype ABI support, rectangular render-target clears, null GPU resource handling,
guest buffer synchronization, and the existing opt-in diagnostic helpers. The
latest upstream controller, audio, SteamVR, geometry-shader, spectator-view, and
Astro Bot fixes remain in the source. Statik's atlas and overlays also work through
the spectator composition path.

## Build and quick checks

Requirements: Windows, Visual Studio 2022 or C++ Build Tools with a Windows SDK,
CMake and Ninja, Git, and LLVM with `clang-cl`, `llvm-lib`, and `llvm-rc`. The local
development toolchain is LLVM 21.1.8. No Sony SDK is needed.

Initialize the pinned dependencies once, then build from PowerShell:

```powershell
git submodule update --init --recursive
.\tools\build_pcvr_release.ps1 -LlvmDirectory C:\path\to\llvm\bin
.\tools\test_pcvr_release.ps1 -LlvmDirectory C:\path\to\llvm\bin -BuildDirectory .\build\pcvr_release
```

Use `-BuildDirectory` to choose another build folder. `-ConfigureOnly` stops after
configuration. `-FFmpegArchive` accepts the prebuilt archive for the pinned
`ext-ffmpeg-core` revision `94dde08`; otherwise CMake retrieves that archive.
The quick checks cover the Statik fixes, overlapping upstream VR/input helpers,
and launcher/package validation. They do not establish headset correctness.

## Stage and launch a local build

Use PkgTool / LibOrbisPkg v0.2 (assemblies 0.2.231) for optional package extraction:

```powershell
.\tools\build_statik_beta.ps1 -Destination .\build\statik_local -PkgToolDirectory C:\path\to\pkgtool
& ".\Play Statik VR.cmd"
```

The destination must be new. Packaging uses explicit source files and clean
defaults. It does not copy a used emulator profile, saves, games, or modules.
The emulator runs from `build\statik_local\runtime`. Choose **Headset (OpenXR)**
after connecting the headset through Virtual Desktop or your OpenXR software.
**Desktop preview** provides a stereo view with synthetic tracking for a basic
startup check. The launcher prompts for the game and system module when needed.

Settings live in the staged folder's `settings.json`; saves live in
`runtime\user\home`. Local staging and build output are ignored by Git. A used
staged folder may contain private paths, modules and saves: do not upload it.

## Headset acceptance check

On the newly built executable, check stereo depth and eye alignment, head and
controller tracking, recentering, menu/pause overlays in both eyes, laser/effects
in both eyes, sound, and at least one level transition. Verify save loading and
normal exit. This is the user's acceptance test after the basic build checks.

## Source and release preparation

`tools/snapshot_statik_source.ps1` exports an allowlisted source snapshot with a
hash manifest. Build and packaging scripts, source, tests, and dependency sources
are included; game data, user profiles, downloaded toolchains and generated
binaries are excluded. The source export supports building without Git metadata.

The existing dependency inventories and notices remain useful preparation inputs.
`statik_beta/release_audit.txt` records the older candidate's evidence and unresolved
release concerns; it is not validation of this new port. FDK-AAC compatibility,
static dependency source/relinking obligations, and provenance review remain
unresolved. This local port does not change the inherited decoder or assert release
clearance. Review those matters before publishing a release.
