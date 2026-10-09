# Third-party notices

StatikQuest is GPL-2.0-or-later (see [LICENSE](LICENSE)), derived from
[AstroQuest](https://github.com/bigmak94/AstroQuest), shadPS4 and the
shadps4-arm64 source. Original notices are retained in the emulator source.

## Windows PC build

| Part | License/source |
| --- | --- |
| Emulator and Statik launcher | GPL-2.0-or-later; this repository |
| Libraries in `shadps4-arm64-main/externals` | Their own licenses in each dependency; pinned sources in [.gitmodules](.gitmodules) |
| Khronos OpenXR loader | Apache-2.0; `externals/openxr-sdk`, [KhronosGroup/OpenXR-SDK](https://github.com/KhronosGroup/OpenXR-SDK) |
| Optional PkgTool / LibOrbisPkg 0.2.231 | LGPL-3.0; unchanged upstream tools, [maxton/LibOrbisPkg v0.2](https://github.com/maxton/LibOrbisPkg/releases/tag/v0.2) |

The Microsoft Visual C++ runtime is required and is not included.
No standalone Quest APK or Android runtime is packaged by this fork's release
scripts. Generic upstream architecture code/attributions remain in the inherited
emulator source; their presence is not a standalone Quest distribution.

## Not included

No game data, PS4 firmware, decrypted system modules, keys, saves or proprietary
SDK files are part of this repository. Used `pc-vr/user` profiles and personal
settings must not be included in release staging.
