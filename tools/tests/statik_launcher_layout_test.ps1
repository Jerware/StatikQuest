$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot)
$launcher = Join-Path $repo 'pc-vr\launch.ps1'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($launcher,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw $errors[0] }
$text=[IO.File]::ReadAllText($launcher)
foreach ($forbidden in @('Frames a second, at most','Resolution of each eye','Save-Setting "fps"',
    'Save-Setting "resolution"','SHADPS4_TITLE_EYE_WIDTH','SHADPS4_VR_FPS_CAP','SHADPS4_TITLE_RESOLUTION',
    'SHADPS4_VR_FASTEST_PACE','SHADPS4_TITLE_TIMESTEP','ASTRO BOT Rescue Mission','Astro Bot VR','CUSA12392')) {
    if ($text.Contains($forbidden)) { throw "Obsolete Astro-only launcher feature: $forbidden" }
}
foreach ($required in @('Console language','Field of view','Desktop view','Show this window at every start','Statik VR')) {
    if (-not $text.Contains($required)) { throw "Missing retained launcher feature: $required" }
}
$bat=[IO.File]::ReadAllText((Join-Path $repo 'Play Statik VR.bat'))
if (-not $bat.Contains('pc-vr\launch.ps1') -or $bat -match 'Astro Bot') { throw 'Batch entry point does not target the Statik PC launcher.' }
. $launcher -CheckOnly
if ($madeFor -ne 'CUSA06929') { throw 'Wrong supported game ID.' }
$script:settings=[ordered]@{desktop_view='combined';desktop_crop='1'}
if ((Get-DesktopView) -ne 'combined') { throw 'Combined spectator selection failed.' }
$script:settings=[ordered]@{desktop_view='spectator'}
if ((Get-DesktopView) -ne 'spectator') { throw 'Single-eye spectator selection failed.' }
$script:settings=[ordered]@{desktop_view='unknown'}
if ((Get-DesktopView) -ne 'stereo') { throw 'Invalid spectator mode must fall back to stereo.' }
foreach ($runtime in @('steamvr','virtualdesktop','')) {
    $instructions=(Get-VrInstructions $runtime)-join "`n"
    if ($instructions -match 'jump|punch|catapult|throwing stars') { throw 'Astro Bot controls remain in Statik instructions.' }
}
if (Test-StatikModule (Join-Path $repo 'LICENSE')) { throw 'Non-ELF file accepted as a system module.' }
$defaults=[IO.File]::ReadAllText((Join-Path $repo 'pc-vr\settings.txt'))
if ($defaults -match '(?m)^\s*(resolution|fps|dynamic|pace|real_time)\s*=') { throw 'Astro-only settings remain in template.' }
Write-Output 'PASS Statik launcher layout: no resolution/FPS overrides, Statik-only branding, .bat entry point and shared VR settings retained.'
