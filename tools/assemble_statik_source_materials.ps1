param([Parameter(Mandatory=$true)][string]$SourceDirectory,
    [Parameter(Mandatory=$true)][string]$UpstreamDirectory,
    [Parameter(Mandatory=$true)][string]$NoticeDirectory,
    [Parameter(Mandatory=$true)][string]$Destination,
    [string]$ReadmePath='',
    [string]$FFmpegConfiguration='')
$ErrorActionPreference='Stop'
$Destination=[IO.Path]::GetFullPath($Destination)
if(Test-Path -LiteralPath $Destination) { throw 'Destination must be new.' }
$upstream=Get-Content (Join-Path $UpstreamDirectory 'download_manifest.json') -Raw | ConvertFrom-Json
$approved=@('ffmpeg_7.1.1.tar.gz','liborbispkg_72370ca.zip','vcpkg_df8bfe5.zip')
# Only these hash-verified public upstream archives may enter the companion.
foreach($name in $approved) {
    $entry=@($upstream | Where-Object file -EQ $name)
    if($entry.Count -ne 1 -or (Get-FileHash (Join-Path $UpstreamDirectory $name)).Hash -ne $entry[0].sha256) { throw "Unverified source archive: $name" }
}
[void][IO.Directory]::CreateDirectory((Join-Path $Destination 'upstream'))
foreach($name in $approved) { Copy-Item -LiteralPath (Join-Path $UpstreamDirectory $name) -Destination (Join-Path $Destination 'upstream') }
Copy-Item -LiteralPath (Join-Path $UpstreamDirectory 'download_manifest.json') -Destination (Join-Path $Destination 'upstream')
# Copy original FFmpeg recipe, patches and triplets from the corresponding source.
$recipe=Join-Path $SourceDirectory 'shadps4-arm64-main/externals/ffmpeg-core'
$target=Join-Path $Destination 'ffmpeg_recipe'
[void][IO.Directory]::CreateDirectory($target)
foreach($name in @('ffmpeg.patch','copyright')) { Copy-Item -LiteralPath (Join-Path $recipe $name) -Destination $target }
Copy-Item -LiteralPath (Join-Path $recipe 'triplets') -Destination $target -Recurse
Copy-Item -LiteralPath (Join-Path $recipe '.github/workflows/build.yml') -Destination (Join-Path $target 'upstream_build.yml')
Copy-Item -LiteralPath $NoticeDirectory -Destination (Join-Path $Destination 'notices') -Recurse
Copy-Item -LiteralPath (Join-Path $SourceDirectory 'build_instructions.txt') -Destination $Destination
if($ReadmePath) { Copy-Item -LiteralPath $ReadmePath -Destination (Join-Path $Destination 'readme.txt') }
if($FFmpegConfiguration) { Copy-Item -LiteralPath $FFmpegConfiguration -Destination (Join-Path $Destination 'ffmpeg_binary_configuration.json') }
$records=@(Get-ChildItem -LiteralPath $Destination -File -Recurse | ForEach-Object {
    if($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked file in materials.' }
    [pscustomobject]@{path=$_.FullName.Substring($Destination.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
})
$records | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $Destination 'materials_manifest.json') -Encoding UTF8
Write-Output "Assembled $($records.Count) companion files. This is not compatibility clearance or proof of a complete FFmpeg rebuild."
