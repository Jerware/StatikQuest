# Building StatikQuest on Windows

These instructions build the PC VR emulator from source. The repository does
not include an executable, game, decrypted system module or personal profile.

## Requirements

- Git, with recursive submodules initialized.
- Visual Studio C++ Build Tools, the Windows SDK and the CMake/Ninja components.
- LLVM with `clang-cl`, `llvm-lib` and `llvm-rc`. LLVM 21.1.8 was used locally.
- Network access for dependencies not already available locally.

No Sony SDK is required. Run the following commands from the repository root,
replacing the example LLVM path with your installation.

```powershell
git submodule update --init --recursive
.\tools\build_pcvr_release.ps1 -LlvmDirectory C:\path\to\llvm\bin
.\tools\test_pcvr_release.ps1 -LlvmDirectory C:\path\to\llvm\bin -BuildDirectory .\build\pcvr_release
.\tools\make-pc-vr.ps1
```

The build is placed in `build/pcvr_release`; staging copies the executable to
`pc-vr/shadps4.exe`. Close the emulator before staging. Existing local settings,
modules and saves are preserved. Start `Play Statik VR.bat` after staging.

## Optional package extraction

Already extracted games do not need PkgTool. For `.pkg` extraction, supply
PkgTool / LibOrbisPkg v0.2.231 with `PkgTool.exe`, `LibOrbisPkg.dll`, `LICENSE.txt`
and `README.md` in the same folder, then stage it with:

```powershell
.\tools\make-pc-vr.ps1 -PkgToolDirectory C:\path\to\pkgtool
```

The Git Bash entry point is `tools/make-pc-vr.sh`, which calls the same PowerShell
staging script.

## Local packaging

`tools/make-release.ps1 -Version <version> -PkgToolDirectory C:\path\to\pkgtool`
makes a new PC-only staging folder, ZIP and `SHA256SUMS.txt` under
`build/release/<version>`. The equivalent
Git Bash entry point is `tools/make-release.sh <version>`; supply PkgTool under
`tools/pkgtool` for its defaults. Existing staging folders are never overwritten.

Packaging uses an explicit allowlist and fresh default configuration, not your
used profile. It follows AstroQuest's PC release layout: a short `README.txt`,
`LICENSE.txt`, a game-folder hint, PkgTool and a pristine input/save profile.
Controller bindings are derived from the emulator source, not a played profile.
It excludes personal settings, games, decrypted modules and saves.
It does not upload anything or establish release clearance: review the unresolved
obligations in [third-party notices](../THIRD-PARTY-NOTICES.md) before distributing
binaries.

## Source layout

- `pc-vr/`: launcher, package validation and tracked default settings.
- `shadps4-arm64-main/`: inherited emulator source and dependencies. The upstream
  folder name is retained; this fork does not provide a standalone Quest app.
- `tools/`: build, staging and regression-test helpers.
- `docs/`: documentation and the selected README screenshot.
- `build/`: ignored local build and packaging output.
