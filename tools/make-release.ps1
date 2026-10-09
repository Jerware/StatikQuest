param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')][string]$Version,
      [string]$EmulatorPath = (Join-Path $PSScriptRoot '..\pc-vr\shadps4.exe'),
      [string]$PkgToolDirectory = (Join-Path $PSScriptRoot 'pkgtool'))
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$out = [IO.Path]::GetFullPath((Join-Path $repo 'build\release'))
$name = "StatikQuest-$Version-PC-VR-Windows"
$dest = Join-Path $out $name
$zip = Join-Path $out ($name+'.zip')
if (Test-Path -LiteralPath $dest) { throw 'Staging folder already exists. Choose another version; nothing will be overwritten.' }
if (Test-Path -LiteralPath $zip) { throw 'Archive already exists. Choose another version; nothing will be overwritten.' }
if (-not (Test-Path -LiteralPath $EmulatorPath -PathType Leaf)) { throw 'Build/stage the emulator first.' }
foreach ($file in @('PkgTool.exe','LibOrbisPkg.dll','LICENSE.txt','README.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PkgToolDirectory $file))) { throw "PkgTool dependency missing: $file" }
}
[void][IO.Directory]::CreateDirectory((Join-Path $dest 'pc-vr\user'))
[void][IO.Directory]::CreateDirectory((Join-Path $dest 'pc-vr\pkgtool'))
[void][IO.Directory]::CreateDirectory((Join-Path $dest 'games'))
[void][IO.Directory]::CreateDirectory((Join-Path $dest 'docs\images'))
foreach ($file in @('Play Statik VR.bat','README.md','README-PC-VR.md','LICENSE','THIRD-PARTY-NOTICES.md')) {
    Copy-Item -LiteralPath (Join-Path $repo $file) -Destination (Join-Path $dest $file)
}
foreach ($file in @('docs\BUILDING.md','docs\images\statik-gameplay.png')) {
    Copy-Item -LiteralPath (Join-Path $repo $file) -Destination (Join-Path $dest $file)
}
foreach ($file in @('launch.ps1','settings.txt','package_setup.ps1','default_config.json')) {
    Copy-Item -LiteralPath (Join-Path $repo "pc-vr\$file") -Destination (Join-Path $dest "pc-vr\$file")
}
Copy-Item -LiteralPath $EmulatorPath -Destination (Join-Path $dest 'pc-vr\shadps4.exe')
Copy-Item -LiteralPath (Join-Path $repo 'pc-vr\default_config.json') -Destination (Join-Path $dest 'pc-vr\user\config.json')
foreach ($file in @('PkgTool.exe','LibOrbisPkg.dll','LICENSE.txt','README.md')) {
    Copy-Item -LiteralPath (Join-Path $PkgToolDirectory $file) -Destination (Join-Path $dest "pc-vr\pkgtool\$file")
}
# Explicit source allowlist above: never copy a used profile or personal settings.
Compress-Archive -LiteralPath $dest -DestinationPath $zip -CompressionLevel Optimal
Write-Output "Local PC staging archive: $zip"
Write-Output ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash + '  ' + [IO.Path]::GetFileName($zip))
Write-Warning 'Local staging only: inherited source/license release audit remains unresolved. Nothing was uploaded.'
