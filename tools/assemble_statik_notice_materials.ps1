param([Parameter(Mandatory=$true)][string]$SourceDirectory,
    [Parameter(Mandatory=$true)][string]$AuditDirectory,
    [Parameter(Mandatory=$true)][string]$Destination,
    [string]$UpstreamDirectory='')
$ErrorActionPreference='Stop'
$SourceDirectory=(Resolve-Path -LiteralPath $SourceDirectory).Path
$AuditDirectory=(Resolve-Path -LiteralPath $AuditDirectory).Path
$Destination=[IO.Path]::GetFullPath($Destination)
if(Test-Path -LiteralPath $Destination) { throw 'Choose a new destination.' }
$records=[Collections.Generic.List[object]]::new()
function Copy-Notice([string]$source,[string]$relative) {
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing notice source: $source" }
    $target=[IO.Path]::GetFullPath((Join-Path $Destination $relative))
    if(-not $target.StartsWith($Destination+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe notice path.' }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    Copy-Item -LiteralPath $source -Destination $target
    $records.Add([pscustomobject]@{path=$relative.Replace('\','/');sha256=(Get-FileHash -LiteralPath $target).Hash})
}
# Preserve the complete collected superset, including notices for source-only
# dependencies. It is not a claim that every component is linked into Windows.
foreach($entry in (Get-Content (Join-Path $AuditDirectory 'license_index.json') -Raw | ConvertFrom-Json)) {
    $source=Join-Path (Join-Path $AuditDirectory 'license_texts') $entry.path
    if((Get-FileHash -LiteralPath $source).Hash -ne $entry.sha256) { throw "Notice hash mismatch: $($entry.path)" }
    Copy-Notice $source ('collected/'+$entry.path)
}
foreach($file in Get-ChildItem (Join-Path $AuditDirectory 'font_notices') -File) {
    Copy-Notice $file.FullName ('fonts/'+$file.Name)
}
$extra=@('freetype/docs/FTL.TXT','freetype/docs/GPLv2.TXT',
    'freetype/src/bdf/README','freetype/src/pcf/README',
    'freetype/src/base/fthash.c','freetype/include/freetype/internal/fthash.h',
    'freetype/src/gzip/zlib.h','freetype/src/autofit/ft-hb-ft.c',
    'freetype/src/autofit/ft-hb-decls.h','freetype/src/autofit/ft-hb-types.h',
    'freetype/src/autofit/hb-script-list.h','renderdoc/renderdoc_app.h','stb/stb_image.h')
foreach($relative in $extra) {
    Copy-Notice (Join-Path $SourceDirectory ('shadps4-arm64-main/externals/'+$relative)) ('referenced/'+$relative)
}
foreach($file in Get-ChildItem (Join-Path $SourceDirectory 'shadps4-arm64-main/externals/gcn/include/gcn') -File) {
    Copy-Notice $file.FullName ('referenced/gcn/'+$file.Name)
}
$records | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $Destination 'notice_manifest.json') -Encoding UTF8
if($UpstreamDirectory) {
    Copy-Notice (Join-Path $UpstreamDirectory 'compiler_rt_21.1.8_license.txt') 'referenced/compiler_rt/license.txt'
    $records | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $Destination 'notice_manifest.json') -Encoding UTF8
}
Write-Output "Collected $($records.Count) notice/source files. Component review and license compatibility are NOT established by this collection."
