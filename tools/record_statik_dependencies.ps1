param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$records=[Collections.Generic.List[object]]::new()
function Record-Repository([string]$path,[string]$relative) {
    $commit=(& git -c safe.directory='*' -C $path rev-parse HEAD)
    if ($LASTEXITCODE -ne 0) { throw "Cannot read revision for $relative" }
    $changes=@(& git -c safe.directory='*' -C $path status --porcelain --untracked-files=no)
    $remote=(& git -c safe.directory='*' -C $path config --get remote.origin.url)
    $records.Add([pscustomobject]@{path=$relative;commit=$commit;remote=$remote;tracked_changes=$changes})
    $entries=@(& git -c safe.directory='*' -C $path ls-files --stage)
    foreach ($entry in $entries) {
        if ($entry -match '^160000 [0-9a-f]+ 0\t(.+)$') {
            $child=$Matches[1]
            Record-Repository (Join-Path $path $child) (($relative.TrimEnd('/')+'/'+$child).TrimStart('./'))
        }
    }
}
Record-Repository $repo '.'
$records | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputDirectory 'dependency_revisions.json') -Encoding UTF8
$licenses=@(& git -c safe.directory='*' -C $repo ls-files --recurse-submodules | Where-Object {
    $_ -match '^shadps4-arm64-main/' -and [IO.Path]::GetFileName($_) -match '^(?i)(LICENSE|COPYING|COPYRIGHT|NOTICE|OFL|UNLICENSE)([._-].*|$)'
})
$index=[Collections.Generic.List[object]]::new()
foreach ($relative in $licenses) {
    $source=Join-Path $repo $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
    $target=Join-Path (Join-Path $OutputDirectory 'license_texts') $relative
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    Copy-Item -LiteralPath $source -Destination $target
    $index.Add([pscustomobject]@{path=$relative;sha256=(Get-FileHash -LiteralPath $target).Hash})
}
$index | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'license_index.json') -Encoding UTF8
Write-Output "Recorded $($records.Count) repositories and $($index.Count) license/notice files. This inventory still requires component-level review."
