param([Parameter(Mandatory=$true)][string]$VcpkgArchive,
    [Parameter(Mandatory=$true)][string]$Patch,
    [Parameter(Mandatory=$true)][string]$Configuration)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$temp=Join-Path $base ('statik_ffmpeg_'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $temp 'ports/ffmpeg'))
try {
    $zip=[IO.Compression.ZipFile]::OpenRead($VcpkgArchive)
    try {
        $entry=@($zip.Entries | Where-Object FullName -EQ 'vcpkg-df8bfe519564ae001903e5cdd32af0999531ef71/ports/ffmpeg/portfile.cmake')
        if($entry.Count -ne 1) { throw 'Pinned portfile not found.' }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry[0],(Join-Path $temp 'ports/ffmpeg/portfile.cmake'))
    } finally { $zip.Dispose() }
    & git -C $temp apply --check --ignore-space-change --ignore-whitespace ([IO.Path]::GetFullPath($Patch))
    if($LASTEXITCODE -ne 0) { throw 'FFmpeg patch does not apply to pinned port.' }
    $actual=(Get-Content -LiteralPath $Configuration -Raw | ConvertFrom-Json).configuration
    $patchText=Get-Content -LiteralPath $Patch -Raw
    $flags=@([regex]::Matches($patchText,'--enable-(?:decoder|encoder|demuxer|muxer|parser|protocol|bsf|indev)=[a-z0-9_]+') | ForEach-Object Value | Select-Object -Unique)
    foreach($flag in $flags) {
        if($actual -notmatch ('(?:^|\s)'+[regex]::Escape($flag)+'(?:\s|$)')) { throw "Missing configured feature: $flag" }
    }
    if($actual -match '(?:^|\s)--enable-(?:gpl|nonfree|libfdk-aac)(?:\s|$)') { throw 'Unexpected restricted feature in FFmpeg configuration.' }
    foreach($flag in @('--disable-libfdk-aac','--disable-openssl','--disable-autodetect','--disable-everything','--toolchain=msvc','--arch=x86_64')) {
        if($actual -notmatch [regex]::Escape($flag)) { throw "Expected configuration missing: $flag" }
    }
    Write-Output "PASS pinned vcpkg patch applies; all $($flags.Count) selected codec/container/parser/protocol features match actual prebuilt configuration."
    Write-Output 'This checks recipe correspondence, not binary identity or independent FFmpeg compilation.'
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    if([IO.Path]::GetDirectoryName($resolved) -ne $base -or [IO.Path]::GetFileName($resolved) -notmatch '^statik_ffmpeg_[0-9a-f]{32}$') { throw 'Unsafe cleanup.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
