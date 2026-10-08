param(
    [string]$BuildDirectory = (Join-Path $PSScriptRoot '..\build\pcvr_release'),
    [string]$PkgToolDirectory = ''
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$build = [IO.Path]::GetFullPath($BuildDirectory)
$exe = Join-Path $build 'shadps4.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Build the Release emulator first.' }
$dest = Join-Path $repo 'pc-vr'
if (Get-Process shadps4 -ErrorAction SilentlyContinue) { throw 'Close the running emulator before updating it.' }
if ($PkgToolDirectory) {
    foreach ($name in @('PkgTool.exe','LibOrbisPkg.dll','LICENSE.txt','README.md')) {
        if (-not (Test-Path -LiteralPath (Join-Path $PkgToolDirectory $name))) { throw "PkgTool dependency missing: $name" }
    }
}
Copy-Item -LiteralPath $exe -Destination (Join-Path $dest 'shadps4.exe')
$profile = Join-Path $dest 'user'
[void][IO.Directory]::CreateDirectory($profile)
$config = Join-Path $profile 'config.json'
if (-not (Test-Path -LiteralPath $config)) {
    Copy-Item -LiteralPath (Join-Path $dest 'default_config.json') -Destination $config
}
foreach ($name in @('savedata','trophy','inputs')) {
    [void][IO.Directory]::CreateDirectory((Join-Path $profile "home\1000\$name"))
}
if ($PkgToolDirectory) {
    [void][IO.Directory]::CreateDirectory((Join-Path $dest 'pkgtool'))
    foreach ($name in @('PkgTool.exe','LibOrbisPkg.dll','LICENSE.txt','README.md')) {
        Copy-Item -LiteralPath (Join-Path $PkgToolDirectory $name) -Destination (Join-Path $dest "pkgtool\$name")
    }
}
Write-Output 'Staged pc-vr/shadps4.exe. Existing settings, saves and modules were preserved.'
