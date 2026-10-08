param([Parameter(Mandatory=$true)][string]$Archive,
    [Parameter(Mandatory=$true)][string]$Library,
    [Parameter(Mandatory=$true)][string]$OutputFile)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputFile) { throw 'Choose a new evidence filename.' }
$bytes=[IO.File]::ReadAllBytes($Library)
$content=[Text.Encoding]::ASCII.GetString($bytes)
$configs=@([regex]::Matches($content,'[\x20-\x7e]{20,}') | Where-Object Value -Match '--enable-pic' | ForEach-Object Value | Select-Object -Unique)
if($configs.Count -ne 1 -or $configs[0] -notmatch '--toolchain=msvc') { throw 'Expected one MSVC FFmpeg configuration string.' }
[ordered]@{
    archive_sha256=(Get-FileHash -LiteralPath $Archive).Hash
    avcodec_sha256=(Get-FileHash -LiteralPath $Library).Hash
    configuration=$configs[0]
    evidence='Configuration string extracted from the linked avcodec static library. Not proof of an independent source rebuild.'
    fdk_note='This FFmpeg configuration disables libfdk-aac. The emulator separately links FDK-AAC; that compatibility concern is unchanged.'
} | ConvertTo-Json | Set-Content -LiteralPath $OutputFile -Encoding UTF8
Write-Output 'Recorded actual prebuilt FFmpeg configuration and hashes.'
