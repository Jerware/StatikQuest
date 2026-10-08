param([Parameter(Mandatory=$true)][string]$SourceDirectory)
$ErrorActionPreference='Stop'
$SourceDirectory=(Resolve-Path -LiteralPath $SourceDirectory).Path
$repo=Split-Path $PSScriptRoot
# Run only after the full source hash pass has completed. Copy the final two
# preparation additions and this script; preserve all other verified entries.
$paths=@('tools/assemble_statik_source_materials.ps1',
    'tools/tests/statik_packaging_repeat_test.ps1','tools/reconcile_statik_preparation.ps1',
    'statik_beta/readme.txt','statik_beta/release_audit.txt')
$manifestPath=Join-Path $SourceDirectory 'source_manifest.json'
$entries=@(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)
$map=@{}; foreach($entry in $entries) { $map[$entry.path]=$entry }
$changes=[Collections.Generic.List[object]]::new()
foreach($relative in $paths) {
    $from=Join-Path $repo $relative; $to=Join-Path $SourceDirectory $relative
    $old=$map[$relative].sha256
    if(Test-Path -LiteralPath $to) {
        if((Get-FileHash -LiteralPath $to).Hash -ne $old) { throw "Unrecorded edit before final copy: $relative" }
    } elseif($old) { throw "Missing source file: $relative" }
    Copy-Item -LiteralPath $from -Destination $to
    $hash=(Get-FileHash -LiteralPath $to).Hash
    $map[$relative]=[pscustomobject]@{path=$relative;sha256=$hash}
    $changes.Add([pscustomobject]@{path=$relative;old_sha256=$old;new_sha256=$hash})
}
$map.Values | Sort-Object path | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$changePath=Join-Path $SourceDirectory 'manifest_changes.json'
$previous=@(Get-Content -LiteralPath $changePath -Raw | ConvertFrom-Json)
@($previous)+@($changes.ToArray()) | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $changePath -Encoding UTF8
$statusPath=Join-Path $SourceDirectory 'snapshot_status.json'
$status=Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
$status.last_manifest_files=$map.Count; $status.manifest_needs_refresh=$false
$status | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statusPath -Encoding UTF8
Write-Output "Reconciled $($paths.Count) explicit preparation files after full hash pass; manifest contains $($map.Count) files. No emulator source changed."
