$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot)
. (Join-Path $repo 'pc-vr\launch.ps1') -CheckOnly | Out-Null
if (-not (Get-GameError '')) { throw 'Empty game must be rejected.' }
if (-not (Get-GameError (Join-Path $repo 'LICENSE'))) { throw 'Non-game file must be rejected.' }
$tokens = $null; $errors = $null
[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'pc-vr\launch.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw $errors[0] }
Write-Output 'Launcher parsing and invalid-game checks passed.'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('statik_sfo_'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $testRoot 'sce_sys'))
try {
    $gamePath=Join-Path $testRoot 'eboot.bin'
    [IO.File]::WriteAllBytes($gamePath,[byte[]]@(0))
    $sfoPath=Join-Path $testRoot 'sce_sys/param.sfo'
    if((Get-GameError $gamePath) -notlike '*missing*') { throw 'Missing SFO accepted.' }
    function Write-TestSfo([string]$title,[string]$category) {
        $keys=[Text.Encoding]::ASCII.GetBytes("TITLE_ID`0CATEGORY`0")
        $titleBytes=[Text.Encoding]::UTF8.GetBytes($title+[char]0)
        $categoryBytes=[Text.Encoding]::UTF8.GetBytes($category+[char]0)
        $memory=[IO.MemoryStream]::new(); $writer=[IO.BinaryWriter]::new($memory)
        try {
            $writer.Write([uint32]0x46535000); $writer.Write([uint32]0x101)
            $writer.Write([uint32]52); $writer.Write([uint32](52+$keys.Length)); $writer.Write([uint32]2)
            $writer.Write([uint16]0); $writer.Write([uint16]0x204)
            $writer.Write([uint32]$titleBytes.Length); $writer.Write([uint32]$titleBytes.Length); $writer.Write([uint32]0)
            $writer.Write([uint16]9); $writer.Write([uint16]0x204)
            $writer.Write([uint32]$categoryBytes.Length); $writer.Write([uint32]$categoryBytes.Length); $writer.Write([uint32]$titleBytes.Length)
            $writer.Write($keys); $writer.Write($titleBytes); $writer.Write($categoryBytes)
            [IO.File]::WriteAllBytes($sfoPath,$memory.ToArray())
        } finally { $writer.Dispose(); $memory.Dispose() }
    }
    Write-TestSfo 'CUSA06929' 'gd'
    if(Get-GameError $gamePath) { throw 'Correct base-game metadata rejected.' }
    Write-TestSfo 'CUSA00000' 'gd'
    if((Get-GameError $gamePath) -notlike '*CUSA06929 only*') { throw 'Wrong title accepted.' }
    Write-TestSfo 'CUSA06929' 'gp'
    if((Get-GameError $gamePath) -notlike '*base game*') { throw 'Update metadata accepted.' }
    Write-TestSfo 'prefixCUSA06929suffix' 'gd'
    if((Get-GameError $gamePath) -notlike '*CUSA06929 only*') { throw 'Substring title accepted.' }
    [IO.File]::WriteAllBytes($sfoPath,[byte[]]@(1,2,3))
    if((Get-GameError $gamePath) -notlike '*invalid or unreadable*') { throw 'Truncated SFO accepted.' }
    Write-Output 'PASS launcher SFO: correct base game, wrong title, substring title, update, missing and truncated metadata.'
} finally {
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notmatch '^statik_sfo_[0-9a-f]{32}$') { throw 'Unsafe test cleanup.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
$frameRoot=Join-Path ([IO.Path]::GetTempPath()) ('statik_fps_'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($frameRoot)
try {
    $ini=[IO.Path]::Combine($frameRoot,'deadlock','saved','config','ps4','engine.ini')
    $script:settings=[ordered]@{frame_rate='240'}
    if((Get-FrameRate) -ne '90') { throw 'An unknown frame rate must fall back to 90.' }
    $script:settings=[ordered]@{frame_rate='60'}
    if((Get-FrameRate) -ne '60' -or (Get-FrameRateRefresh '90') -ne '90' -or (Get-FrameRateRefresh '60') -ne '120') { throw 'Frame rate or headset refresh misread.' }
    Set-FrameRate $frameRoot '120'
    $text=[IO.File]::ReadAllText($ini)
    if($text -notmatch 'PSVRFrameSequence=Render120Scanout120' -or $text -notmatch 'bSmoothFrameRate=False' -or $text -notmatch 't\.MaxFPS=0') { throw '120 frames a second not written.' }
    Set-FrameRate $frameRoot '90'
    if([IO.File]::ReadAllText($ini) -notmatch 'PSVRFrameSequence=Render90Scanout90') { throw '90 frames a second not written.' }
    Set-FrameRate $frameRoot '60'
    if([IO.Directory]::Exists([IO.Path]::Combine($frameRoot,'deadlock','saved'))) { throw '60 frames a second left the file or its folders behind.' }
    [void][IO.Directory]::CreateDirectory((Split-Path $ini))
    [IO.File]::WriteAllText($ini,"[Core.System]`r`n")
    Set-FrameRate $frameRoot '120' 6>$null
    Set-FrameRate $frameRoot '60' 6>$null
    if([IO.File]::ReadAllText($ini) -ne "[Core.System]`r`n") { throw "An engine.ini the launcher did not write was changed." }
    Write-Output 'PASS launcher frame rate: 120 and 90 written, 60 removes them and their empty folders, unknown values fall back to 90, a foreign engine.ini is left alone.'
} finally {
    $resolved=[IO.Path]::GetFullPath($frameRoot)
    $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notmatch '^statik_fps_[0-9a-f]{32}$') { throw 'Unsafe test cleanup.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
