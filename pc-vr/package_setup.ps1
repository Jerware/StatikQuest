# GPL-2.0-or-later. Package metadata naming follows AstroQuest's launcher.
function Get-StatikPackageInfo([string]$path) {
    $stream = [IO.File]::OpenRead($path)
    try { $head = New-Object byte[] 128; $read = $stream.Read($head,0,128) } finally { $stream.Dispose() }
    if ($read -ne 128 -or [BitConverter]::ToString($head,0,4) -ne '7F-43-4E-54') { throw 'Not a valid PS4 package header.' }
    $id = [Text.Encoding]::ASCII.GetString($head,64,36).Trim([char]0)
    if ($id -notmatch '^.{7}CUSA06929_') { throw 'StatikQuest accepts Statik CUSA06929 packages only.' }
    if (($head[0x78] -band 0x60) -or ($head[0x79] -band 0x30)) { throw 'This is an update package. Select the full base game; update installation is not supported.' }
    return $id
}
function Read-StatikSfo([string]$path) {
    $b = [IO.File]::ReadAllBytes($path)
    if ($b.Length -lt 20 -or [BitConverter]::ToUInt32($b,0) -ne 0x46535000) { throw 'Invalid param.sfo.' }
    $keys = [BitConverter]::ToUInt32($b,8); $data = [BitConverter]::ToUInt32($b,12)
    $count = [BitConverter]::ToUInt32($b,16); $values = @{}
    if ($count -gt (($b.Length - 20) / 16)) { throw 'Invalid SFO entry count.' }
    for ($i=0; $i -lt $count; $i++) {
        $at=20+16*$i; $k=$keys+[BitConverter]::ToUInt16($b,$at)
        $v=$data+[BitConverter]::ToUInt32($b,$at+12); $n=[BitConverter]::ToUInt32($b,$at+4)
        if ($k -ge $b.Length -or $v+$n -gt $b.Length) { throw 'Invalid SFO bounds.' }
        $end=[Array]::IndexOf($b,[byte]0,[int]$k)
        if ($end -lt $k) { throw 'Invalid SFO key.' }
        if ([BitConverter]::ToUInt16($b,$at+2) -eq 0x204 -and $n -gt 0) {
            $values[[Text.Encoding]::ASCII.GetString($b,$k,$end-$k)] = [Text.Encoding]::UTF8.GetString($b,$v,$n).Trim([char]0)
        }
    }
    return $values
}
function Install-StatikPackage([string]$path, [string]$destinationRoot, [string]$tool, [scriptblock]$runner) {
    $null = Get-StatikPackageInfo $path
    if (-not (Test-Path -LiteralPath $tool)) { throw 'PkgTool is missing. Extract the complete StatikQuest package again.' }
    $games = [IO.Path]::GetFullPath((Join-Path $destinationRoot 'games'))
    $target = Join-Path $games 'cusa06929'
    if (Test-Path -LiteralPath $target) { throw "An installation already exists at $target. Select its eboot.bin; it will not be overwritten." }
    $work = Join-Path $games ('unpacking_' + [Guid]::NewGuid().ToString('N'))
    if ($work.Length -gt 120) { throw 'Move the StatikQuest folder to a shorter path before extracting.' }
    $free = (New-Object IO.DriveInfo([IO.Path]::GetPathRoot($games))).AvailableFreeSpace
    $estimate = (Get-Item -LiteralPath $path).Length * 3 + 1GB
    if ($free -lt $estimate) { throw ('Allow at least {0:N1} GB free for extraction (an estimate).' -f ($estimate/1GB)) }
    [void][IO.Directory]::CreateDirectory($work)
    try {
        $files = Join-Path $work 'files'
        $argsText = 'pkg_extract --passcode ' + ('0'*32) + ' "' + $path + '" "' + $files + '"'
        & $runner $tool $argsText $work
        $unpacked = Join-Path $files 'uroot'
        if (-not (Test-Path -LiteralPath $unpacked)) { $unpacked = $files }
        if (-not (Test-Path -LiteralPath (Join-Path $unpacked 'eboot.bin'))) { throw 'No game executable was extracted. The package may be unsupported or encrypted.' }
        $entries = @(& $tool pkg_listentries $path 2>&1)
        if ($LASTEXITCODE -ne 0) { throw 'Could not read package metadata.' }
        foreach ($line in $entries) {
            if ([string]$line -notmatch '^0x[0-9A-Fa-f]+\s+0x[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\d+)\s+(?:\d+\s+)?([A-Z0-9_]+)\s*$') { continue }
            $index=$Matches[1]; $name=$Matches[2]
            if ($name -notmatch '^(PARAM_SFO|ICON0_PNG|PIC[01]_PNG|PLAYGO_[A-Z0-9_]+|TROPHY__[A-Z0-9_]+)$') { continue }
            $relative=$name.ToLower().Replace('__','\'); $dot=$relative.LastIndexOf('_')
            if ($dot -gt 0) { $relative=$relative.Substring(0,$dot)+'.'+$relative.Substring($dot+1) }
            if ($relative.StartsWith('playgo_')) { $relative='playgo-'+$relative.Substring(7) }
            $out=Join-Path (Join-Path $unpacked 'sce_sys') $relative
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($out))
            & $tool pkg_extractentry --passcode ('0'*32) $path $index $out 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Could not extract metadata: $name" }
        }
        $sfo=Read-StatikSfo (Join-Path $unpacked 'sce_sys\param.sfo')
        if ($sfo.TITLE_ID -ne 'CUSA06929' -or $sfo.CATEGORY -ne 'gd') { throw 'Extracted metadata is not the supported Statik base game.' }
        # Both are explicit child paths of games; Directory.Move refuses an existing target.
        [IO.Directory]::Move($unpacked,$target)
        return Join-Path $target 'eboot.bin'
    } catch {
        throw "Extraction did not finish: $($_.Exception.Message)`nPartial files and logs are retained at $work. Your original package was not changed."
    }
}

function Get-GameError([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return 'Choose the eboot.bin from your extracted Statik game.' }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return 'Choose the eboot.bin from your extracted Statik game.' }
    if ([IO.Path]::GetFileName($path) -ne 'eboot.bin') { return 'Choose eboot.bin, not a package or another file.' }
    $sfo = Join-Path (Split-Path $path) 'sce_sys\param.sfo'
    if (-not (Test-Path -LiteralPath $sfo)) { return 'The game folder is missing sce_sys\param.sfo.' }
    try { $metadata = Read-StatikSfo $sfo } catch { return 'The game metadata is invalid or unreadable.' }
    if ($metadata.TITLE_ID -ne 'CUSA06929') { return 'StatikQuest supports Statik CUSA06929 only. Please select that game version.' }
    if ($metadata.CATEGORY -ne 'gd') { return 'Select the base game, not an extracted update or add-on.' }
    return ''
}
