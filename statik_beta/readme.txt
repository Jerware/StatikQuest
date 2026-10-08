STATIKQUEST PC VR - development build

Unofficial. Based on AstroQuest by bigmak94 and shadPS4 and its contributors.
Windows x64 / PC VR only. No Quest-native build is included.

QUICK START
Extract the entire folder to a writable location. Run play_statik.cmd.
Select eboot.bin inside your extracted Statik CUSA06929 game folder, or select
your base-game .pkg. Compatible packages are extracted once into games\cusa06929.
Original packages are kept. Existing installations are never overwritten.
Update packages and encrypted retail packages are not supported.
Cancelled/failed extractions are retained in games\unpacking_* with their logs.
On first play, select your own decrypted libSceJson2.sprx when prompted.
Connect the headset and start its OpenXR PC connection before pressing Play.
The emulator also opens a visible desktop window.

Requirements: Vulkan-compatible graphics driver, an active OpenXR runtime for VR,
and Microsoft Visual C++ x64 runtime:
https://aka.ms/vs/17/release/vc_redist.x64.exe
The launcher does not download or install prerequisites automatically.
Game files and system modules are not included. Package extraction uses unchanged
PkgTool / LibOrbisPkg 0.2.231 by Maxton (LGPL-3.0; see pkgtool\LICENSE.txt).
Extractor source: https://github.com/maxton/LibOrbisPkg (release v0.2).
Only CUSA06929 is currently accepted. Other regions are not verified.

SETTINGS AND SAVES
Settings: settings.json. Saves: runtime\user\home.
This package starts with fresh saves and never imports your existing saves.
Keep the whole folder when upgrading until save migration has been tested.
Do not share a used package: it can contain your module, saves and local paths.
Troubleshooting logs are off by default. Crash exit codes are still reported.
Resolution and frame-rate overrides specific to Astro Bot are intentionally absent.

STATUS
The older Statik development version has been played through multiple levels,
with stereo, head/controller tracking and pause overlays. Those changes are now
ported onto AstroQuest 0.20. This new executable still needs headset validation;
older results are not acceptance results for this build. Performance varies.
Installation, full-game and headset acceptance testing are being handled by the
beta testers. This is not a finished or universally compatible release.
Share the original Windows archive together with the matching source and dependency
archives. Keep license.txt, gpl_3.0.txt, third_party_notices.txt and notices intact.
Inherited licensing uncertainties are documented in release_audit.txt; this beta
is not a legal-compliance certification. No game, firmware or Sony SDK is supplied.
The launcher's ELF check cannot guarantee module-version compatibility.
