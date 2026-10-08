param([Parameter(Mandatory=$true)][string]$ReferencePackage,
    [Parameter(Mandatory=$true)][string]$EmulatorPath,
    [Parameter(Mandatory=$true)][string]$PkgToolDirectory,
    [Parameter(Mandatory=$true)][string]$NoticeDirectory)
$ErrorActionPreference='Stop'
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$temp=Join-Path $base ('statik_repeat_'+[Guid]::NewGuid().ToString('N'))
try {
    & (Join-Path (Split-Path $PSScriptRoot) 'build_statik_beta.ps1') -Destination $temp -EmulatorPath $EmulatorPath -PkgToolDirectory $PkgToolDirectory -NoticeDirectory $NoticeDirectory | Out-Null
    $ReferencePackage=(Resolve-Path -LiteralPath $ReferencePackage).Path
    $expected=@(Get-ChildItem -LiteralPath $ReferencePackage -File -Recurse | ForEach-Object { $_.FullName.Substring($ReferencePackage.Length+1) } | Sort-Object)
    $actual=@(Get-ChildItem -LiteralPath $temp -File -Recurse | ForEach-Object { $_.FullName.Substring($temp.Length+1) } | Sort-Object)
    if(Compare-Object $expected $actual) { throw 'Packaging file lists differ.' }
    foreach($path in $expected) {
        if($path -eq 'build_manifest.json') { continue }
        if((Get-FileHash (Join-Path $ReferencePackage $path)).Hash -ne (Get-FileHash (Join-Path $temp $path)).Hash) { throw "Packaging content differs: $path" }
    }
    $reference=Get-Content (Join-Path $ReferencePackage 'build_manifest.json') -Raw | ConvertFrom-Json
    $rebuilt=Get-Content (Join-Path $temp 'build_manifest.json') -Raw | ConvertFrom-Json
    foreach($key in @('status','executable_sha256','upstream_base','source_revision','source_dirty')) {
        if($reference.$key -ne $rebuilt.$key) { throw "Build identity differs: $key" }
    }
    Write-Output "PASS repeat packaging: $($expected.Count) files match, excluding only build_manifest.json assembly timestamp. This is packaging reproducibility, not bit-identical compiler output."
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    if([IO.Path]::GetDirectoryName($resolved) -ne $base -or [IO.Path]::GetFileName($resolved) -notmatch '^statik_repeat_[0-9a-f]{32}$') { throw 'Unsafe temporary cleanup.' }
    if(Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
