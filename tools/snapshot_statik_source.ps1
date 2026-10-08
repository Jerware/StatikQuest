param([Parameter(Mandatory=$true)][string]$Destination,
    [string]$EmulatorPath = (Join-Path $PSScriptRoot '..\build\pcvr_release\shadps4.exe'))
$ErrorActionPreference='Stop'
$repo = Split-Path $PSScriptRoot
$Destination = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $Destination) { throw 'Choose an empty, new destination.' }
# Git supplies dependency source names, never an indiscriminate workspace copy.
$tracked = @(& git -c safe.directory='*' -C $repo ls-files --recurse-submodules)
if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate dependency sources.' }
$new = @(& git -c safe.directory='*' -C $repo ls-files --others --exclude-standard -- shadps4-arm64-main/src tools/tests statik_beta)
if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate new source files.' }
$scripts = @(Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object {
    $_.Name -like '*statik*' -or $_.Name -in @('build_pcvr_release.ps1','test_pcvr_release.ps1')
} | ForEach-Object { 'tools/'+$_.Name })
$paths = @($tracked + $new + $scripts | Sort-Object -Unique | Where-Object {
    $_ -match '^(shadps4-arm64-main/|statik_beta/|tools/tests/)' -or $_ -in $scripts -or $_ -in @('LICENSE','.gitignore','.gitmodules','.gitattributes','README-STATIK.md','Play Statik VR.cmd')
})
$manifest = [Collections.Generic.List[object]]::new()
$excluded = [Collections.Generic.List[string]]::new()
[void][IO.Directory]::CreateDirectory($Destination)
foreach ($relative in $paths) {
    if ($relative -match '(?i)(^|/)(build|user|savedata|sce_sys|sce_module)/|(^|/)(eboot\.bin|keys\.json)$|\.(pkg|pup|sprx|prx|self|dll|exe|lib|a|zip|7z|apk|pdf)$') {
        $excluded.Add($relative); continue
    }
    $source = Join-Path $repo $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing tracked source: $relative" }
    $item=Get-Item -LiteralPath $source -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Review linked source: $relative" }
    $target=Join-Path $Destination $relative
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    [IO.File]::Copy($source,$target,$false)
    if ($relative -eq 'shadps4-arm64-main/externals/ffmpeg-core/CMakeLists.txt') {
        # Source exports omit dependency Git metadata. Preserve the checked-in
        # dependency while making the exported recipe accept its pinned revision.
        $text=[IO.File]::ReadAllText($target)
        $command=[regex]::Match($text,'(?s)# Compute current short git commit SHA\r?\nexecute_process\(.*?OUTPUT_STRIP_TRAILING_WHITESPACE\)')
        if(-not $command.Success) { throw 'FFmpeg archive recipe no longer matches the pinned dependency.' }
        $replacement="if(NOT FFMPEG_GIT_SHA)`n"+$command.Value+"`nendif()`nif(NOT FFMPEG_GIT_SHA)`n    message(FATAL_ERROR `"Source archive build requires -DFFMPEG_GIT_SHA=94dde08`")`nendif()"
        [IO.File]::WriteAllText($target,$text.Replace($command.Value,$replacement))
    }
    $manifest.Add([pscustomobject]@{path=$relative;sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash})
}
$manifest | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $Destination 'source_manifest.json') -Encoding UTF8
$excluded | Set-Content (Join-Path $Destination 'excluded_tracked_files.txt') -Encoding UTF8
@{
    upstream=(& git -c safe.directory='*' -C $repo merge-base origin/main HEAD)
    source_revision=(& git -c safe.directory='*' -C $repo rev-parse HEAD)
    source_dirty=@(& git -c safe.directory='*' -C $repo status --porcelain).Count -ne 0
    status='source candidate; exclusions, license completeness and clean rebuild require verification'
    files=$manifest.Count
    executable_sha256=if(Test-Path -LiteralPath $EmulatorPath) { (Get-FileHash -LiteralPath $EmulatorPath).Hash } else { '' }
} | ConvertTo-Json | Set-Content (Join-Path $Destination 'snapshot_status.json') -Encoding UTF8
Write-Output "Source candidate: $Destination ($($manifest.Count) files). Not yet release-cleared."
