param(
    [Parameter(Mandatory=$true)][string]$LlvmDirectory,
    [string]$BuildDirectory = (Join-Path $PSScriptRoot '..\build\pcvr_release'),
    [string]$FFmpegArchive = '',
    [switch]$ConfigureOnly
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot))
$LlvmDirectory=[IO.Path]::GetFullPath($LlvmDirectory)
$BuildDirectory=[IO.Path]::GetFullPath($BuildDirectory)
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'Install Visual Studio C++ build tools with CMake and a Windows SDK.' }
$vs=(& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
if (-not $vs) { throw 'Visual Studio C++ tools not found.' }
$devcmd=Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
cmd.exe /d /s /c "`"$devcmd`" -arch=x64 -host_arch=x64 >nul && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { Set-Item "env:$($Matches[1])" $Matches[2] }
}
$cmake=Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
$ninja=Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja'
foreach($name in @('clang-cl.exe','llvm-rc.exe','llvm-lib.exe')) {
    if(-not (Test-Path (Join-Path $LlvmDirectory $name))) { throw "LLVM tool missing: $name" }
}
$env:PATH="$LlvmDirectory;$ninja;$env:PATH"
if ($FFmpegArchive) {
    [void][IO.Directory]::CreateDirectory((Join-Path $BuildDirectory 'externals'))
    Copy-Item -LiteralPath $FFmpegArchive -Destination (Join-Path $BuildDirectory 'externals\ffmpeg-94dde08.zip')
}
Push-Location -LiteralPath $repo
try {
& $cmake -S "$repo\shadps4-arm64-main" -B $BuildDirectory -G Ninja `
    -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl -DCMAKE_ASM_COMPILER=clang-cl `
    "-DCMAKE_RC_COMPILER:FILEPATH=$LlvmDirectory/llvm-rc.exe" "-DCMAKE_AR:FILEPATH=$LlvmDirectory/llvm-lib.exe" `
    -DCMAKE_BUILD_TYPE=Release -DENABLE_DISCORD_RPC=OFF -DENABLE_UPDATER=OFF -DFFMPEG_GIT_SHA=94dde08 `
    "-DFETCHCONTENT_SOURCE_DIR_FMT=$repo/shadps4-arm64-main/externals/fmt"
if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed.' }
if (-not $ConfigureOnly) {
    & $cmake --build $BuildDirectory --target shadps4 --parallel 6
    if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }
}
} finally { Pop-Location }
