param([Parameter(Mandatory=$true)][string]$ArchivePath,
      [string]$UpstreamArchivePath = '')
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot)
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Read-ZipText($entry) {
    $reader = [IO.StreamReader]::new($entry.Open())
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}
function Get-ZipHash($entry) {
    $stream = $entry.Open()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') } finally { $stream.Dispose(); $sha.Dispose() }
}
$archive = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($ArchivePath))
try {
    $roots = @($archive.Entries | ForEach-Object { $_.FullName.Split('/')[0] } | Select-Object -Unique)
    if ($roots.Count -ne 1 -or $roots[0] -notmatch '^StatikQuest-[A-Za-z0-9._-]+-PC-VR-Windows$') { throw 'Unexpected archive root.' }
    $root = $roots[0] + '/'
    $allowed = @('LICENSE.txt','Play Statik VR.bat','README.txt','THIRD-PARTY-NOTICES.md',
        'games/PUT YOUR GAME HERE.txt','pc-vr/launch.ps1','pc-vr/settings.txt','pc-vr/package_setup.ps1',
        'pc-vr/default_config.json','pc-vr/shadps4.exe','pc-vr/pkgtool/LICENSE.txt',
        'pc-vr/pkgtool/LibOrbisPkg.dll','pc-vr/pkgtool/PkgTool.exe','pc-vr/pkgtool/README.txt',
        'pc-vr/user/config.json','pc-vr/user/input_config/default.ini','pc-vr/user/input_config/global.ini')
    $emptyDirectories = @('pc-vr/user/home/1000/inputs/','pc-vr/user/home/1000/savedata/','pc-vr/user/home/1000/trophy/')
    $entries = @{}
    foreach ($entry in $archive.Entries) {
        $relative = $entry.FullName.Substring($root.Length)
        if ($entries.ContainsKey($relative)) { throw 'Duplicate archive entry.' }
        if ($relative.EndsWith('/')) {
            if ($relative -notin $emptyDirectories -or $entry.Length -ne 0) { throw "Unexpected directory: $relative" }
        } elseif ($relative -notin $allowed) { throw "Unexpected/private release file: $relative" }
        $entries[$relative] = $entry
    }
    foreach ($path in ($allowed + $emptyDirectories)) { if (-not $entries.ContainsKey($path)) { throw "Missing release entry: $path" } }
    foreach ($path in @('pc-vr/default_config.json','pc-vr/user/config.json')) {
        $configText = Read-ZipText $entries[$path]
        $config = $configText | ConvertFrom-Json
        foreach ($key in @('addon_install_dir','font_dir','home_dir','sys_modules_dir','shadnet_server')) {
            if ($config.General.$key -ne '') { throw "Personal path/device in $path" }
        }
        if (@($config.General.install_dirs).Count -ne 0 -or $config.Input.default_controller_id -ne '' -or $config.Vulkan.gpu_id -ne -1) { throw 'Personal device/game configuration included.' }
        if ($configText -match '[A-Za-z]:[\\/]|jer\.williams@gmail\.com') { throw 'Private content in config.' }
    }
    $readme = Read-ZipText $entries['README.txt']
    if ($readme -match '@VERSION@|ASTRO BOT Rescue Mission|Play Astro Bot|120 Hz|libSceJson2\.sprx') { throw 'Unadapted release instructions.' }
    if ($readme -notmatch 'Forward tracking data to PC' -or $readme -notmatch 'CUSA06929') { throw 'Statik setup requirements missing.' }
    $gameHint = Read-ZipText $entries['games/PUT YOUR GAME HERE.txt']
    if ($gameHint -notmatch 'CUSA06929' -or $gameHint -match 'CUSA12392|13 GB') { throw 'Unadapted game hint.' }
    $exeHash = Get-ZipHash $entries['pc-vr/shadps4.exe']
    if ($exeHash -ne (Get-FileHash -LiteralPath (Join-Path $repo 'pc-vr/shadps4.exe')).Hash) { throw 'Tested emulator does not match package.' }
    $expectedHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksum = [IO.File]::ReadAllText((Join-Path (Split-Path $ArchivePath) 'SHA256SUMS.txt')).Trim()
    if ($checksum -cne ($expectedHash + '  ' + [IO.Path]::GetFileName($ArchivePath))) { throw 'Release checksum mismatch.' }
    if ($UpstreamArchivePath) {
        $upstream = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($UpstreamArchivePath))
        try {
            foreach ($path in @('pc-vr/pkgtool/PkgTool.exe','pc-vr/pkgtool/LibOrbisPkg.dll','pc-vr/pkgtool/LICENSE.txt',
                'pc-vr/user/input_config/default.ini','pc-vr/user/input_config/global.ini')) {
                $matches = @($upstream.Entries | Where-Object { $_.FullName.EndsWith('/' + $path) })
                if ($matches.Count -ne 1) { throw "Missing upstream reference: $path" }
                if ($path.EndsWith('.ini')) {
                    $localText = (Read-ZipText $entries[$path]).Replace("`r`n", "`n").Trim()
                    $upstreamText = (Read-ZipText $matches[0]).Replace("`r`n", "`n").Trim()
                    if ($localText -cne $upstreamText) { throw "Input defaults differ from upstream: $path" }
                } elseif ((Get-ZipHash $entries[$path]) -ne (Get-ZipHash $matches[0])) { throw "PkgTool differs from upstream: $path" }
            }
        } finally { $upstream.Dispose() }
    }
    Write-Output 'PASS clean release: explicit file allowlist, empty save profile, private defaults, setup notes, tested executable and checksum.'
    if ($UpstreamArchivePath) { Write-Output 'PASS AstroQuest comparison: identical PkgTool binaries/license and controller defaults.' }
} finally { $archive.Dispose() }
