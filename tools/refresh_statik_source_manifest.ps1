param([Parameter(Mandatory=$true)][string]$SourceDirectory)
$ErrorActionPreference='Stop'
$SourceDirectory=(Resolve-Path -LiteralPath $SourceDirectory).Path
$manifestPath=Join-Path $SourceDirectory 'source_manifest.json'
$previous=@(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)
$map=@{}
foreach($entry in $previous) { $map[$entry.path]=$entry.sha256 }
$changes=[Collections.Generic.List[object]]::new()
$manifest=[Collections.Generic.List[object]]::new()
$excluded=@('source_manifest.json','manifest_changes.json','snapshot_status.json')
foreach($file in Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File -Force) {
    $relative=$file.FullName.Substring($SourceDirectory.Length+1).Replace('\','/')
    if($relative -in $excluded) { continue }
    if($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked file: $relative" }
    if($relative -match '(?i)\.(pkg|pup|sprx|prx|self|exe|dll|lib|a|apk)$|(^|/)(eboot\.bin|keys\.json)$') { throw "Unexpected binary/console file: $relative" }
    $stream=[IO.File]::OpenRead($file.FullName)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $hash=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
    finally { $sha.Dispose(); $stream.Dispose() }
    $manifest.Add(@{path=$relative;sha256=$hash})
    if($map[$relative] -ne $hash) { $changes.Add(@{path=$relative;old_sha256=$map[$relative];new_sha256=$hash}) }
    $map.Remove($relative)
    if($manifest.Count % 5000 -eq 0) { Write-Output "Hashed $($manifest.Count) files..." }
}
if($map.Count) { throw 'Source files were removed since export; review before regenerating manifest.' }
$manifest | ConvertTo-Json -Depth 3 | Set-Content $manifestPath -Encoding UTF8
$changes | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $SourceDirectory 'manifest_changes.json') -Encoding UTF8
Write-Output "Refreshed $($manifest.Count) source hashes; $($changes.Count) added/changed files recorded."
