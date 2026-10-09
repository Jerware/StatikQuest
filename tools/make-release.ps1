param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')][string]$Version,
      [string]$EmulatorPath = '',
      [string]$PkgToolDirectory = '')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
if (-not $EmulatorPath) { $EmulatorPath = Join-Path $repo 'pc-vr\shadps4.exe' }
if (-not $PkgToolDirectory) { $PkgToolDirectory = Join-Path $PSScriptRoot 'pkgtool' }
$out = [IO.Path]::GetFullPath((Join-Path $repo "build\release\$Version"))
$name = "StatikQuest-$Version-PC-VR-Windows"
$dest = Join-Path $out $name
$zip = Join-Path $out ($name+'.zip')
$checksums = Join-Path $out 'SHA256SUMS.txt'
if (Test-Path -LiteralPath $dest) { throw 'Staging folder already exists. Choose another version; nothing will be overwritten.' }
if (Test-Path -LiteralPath $zip) { throw 'Archive already exists. Choose another version; nothing will be overwritten.' }
if (Test-Path -LiteralPath $checksums) { throw 'Checksum file already exists. Choose another version; nothing will be overwritten.' }
if (-not (Test-Path -LiteralPath $EmulatorPath -PathType Leaf)) { throw 'Build/stage the emulator first.' }
foreach ($file in @('PkgTool.exe','LibOrbisPkg.dll','LICENSE.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PkgToolDirectory $file))) { throw "PkgTool dependency missing: $file" }
}
function Write-ReleaseText([string]$path, [string]$text) {
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}
$assets = Join-Path $PSScriptRoot 'release-assets'
foreach ($file in @('README.txt','PUT YOUR GAME HERE.txt','PkgTool-README.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $assets $file) -PathType Leaf)) { throw "Release template missing: $file" }
}
# Derive pristine input defaults from source, never from the used PC profile.
$inputSource = [IO.File]::ReadAllText((Join-Path $repo 'shadps4-arm64-main\src\input\input_handler.cpp'))
$inputDefault = [regex]::Match($inputSource, '(?s)GetDefaultInputConfig\(\)\s*\{\s*return R"\((.*?)\)";')
$globalDefault = [regex]::Match($inputSource, '(?s)GetDefaultGlobalConfig\(\)\s*\{\s*return R"\((.*?)\)";')
$hotkeyMap = [regex]::Match($inputSource, '(?s)default_bindings_to_add\s*=\s*\{(.*?)\n\s*\};')
if (-not $inputDefault.Success -or -not $globalDefault.Success -or -not $hotkeyMap.Success) { throw 'Cannot derive clean controller defaults from source.' }
$hotkeys = [regex]::Matches($hotkeyMap.Groups[1].Value, '\{"([^"]+)",\s*"([^"]+)"\}') | Sort-Object { $_.Groups[1].Value }
if ($hotkeys.Count -lt 1) { throw 'No default hotkeys found.' }
$globalText = $globalDefault.Groups[1].Value
foreach ($hotkey in $hotkeys) { $globalText += $hotkey.Groups[1].Value + ' = ' + $hotkey.Groups[2].Value + "`n" }
[void][IO.Directory]::CreateDirectory((Join-Path $dest 'pc-vr\user'))
[void][IO.Directory]::CreateDirectory((Join-Path $dest 'pc-vr\pkgtool'))
[void][IO.Directory]::CreateDirectory((Join-Path $dest 'games'))
[void][IO.Directory]::CreateDirectory((Join-Path $dest 'pc-vr\user\input_config'))
foreach ($directory in @('savedata','trophy','inputs')) {
    [void][IO.Directory]::CreateDirectory((Join-Path $dest "pc-vr\user\home\1000\$directory"))
}
foreach ($file in @('Play Statik VR.bat','THIRD-PARTY-NOTICES.md')) {
    Copy-Item -LiteralPath (Join-Path $repo $file) -Destination (Join-Path $dest $file)
}
Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination (Join-Path $dest 'LICENSE.txt')
$readme = [IO.File]::ReadAllText((Join-Path $assets 'README.txt')).Replace('@VERSION@', $Version)
Write-ReleaseText (Join-Path $dest 'README.txt') $readme
Copy-Item -LiteralPath (Join-Path $assets 'PUT YOUR GAME HERE.txt') -Destination (Join-Path $dest 'games\PUT YOUR GAME HERE.txt')
Write-ReleaseText (Join-Path $dest 'pc-vr\user\input_config\default.ini') $inputDefault.Groups[1].Value
Write-ReleaseText (Join-Path $dest 'pc-vr\user\input_config\global.ini') $globalText
foreach ($file in @('launch.ps1','settings.txt','package_setup.ps1','default_config.json')) {
    Copy-Item -LiteralPath (Join-Path $repo "pc-vr\$file") -Destination (Join-Path $dest "pc-vr\$file")
}
Copy-Item -LiteralPath $EmulatorPath -Destination (Join-Path $dest 'pc-vr\shadps4.exe')
Copy-Item -LiteralPath (Join-Path $repo 'pc-vr\default_config.json') -Destination (Join-Path $dest 'pc-vr\user\config.json')
foreach ($file in @('PkgTool.exe','LibOrbisPkg.dll','LICENSE.txt')) {
    Copy-Item -LiteralPath (Join-Path $PkgToolDirectory $file) -Destination (Join-Path $dest "pc-vr\pkgtool\$file")
}
Copy-Item -LiteralPath (Join-Path $assets 'PkgTool-README.txt') -Destination (Join-Path $dest 'pc-vr\pkgtool\README.txt')
# Explicit source allowlist above: never copy a used profile or personal settings.
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
# Windows PowerShell's CreateFromDirectory emits backslashes. Use portable ZIP
# entry names and preserve the empty first-user directories, as AstroQuest does.
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in (Get-ChildItem -LiteralPath $dest -File -Recurse | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($dest.Length + 1).Replace('\', '/')
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName,
            "$name/$relative", [IO.Compression.CompressionLevel]::Optimal)
    }
    foreach ($directory in @('inputs','savedata','trophy')) {
        [void]$archive.CreateEntry("$name/pc-vr/user/home/1000/$directory/")
    }
} finally { $archive.Dispose() }
$checksumLine = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($zip)
Write-ReleaseText $checksums ($checksumLine + "`n")
Write-Output "Local PC staging archive: $zip"
Write-Output $checksumLine
Write-Output "Release checksums: $checksums"
Write-Warning 'Local staging only: inherited source/license release audit remains unresolved. Nothing was uploaded.'
