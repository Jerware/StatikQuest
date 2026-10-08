param([Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference='Stop'
[void][IO.Directory]::CreateDirectory($Destination)
$items=@(
    @{name='liborbispkg_72370ca.zip';url='https://codeload.github.com/maxton/LibOrbisPkg/zip/72370ca3739e0708250695046b3886e50452dee7'},
    @{name='ffmpeg_7.1.1.tar.gz';url='https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/refs/tags/n7.1.1';sha512='6b9a5ee501be41d6abc7579a106263b31f787321cbc45dedee97abf992bf8236cdb2394571dd256a74154f4a20018d429ae7e7f0409611ddc4d6f529d924d175'},
    @{name='vcpkg_df8bfe5.zip';url='https://codeload.github.com/microsoft/vcpkg/zip/df8bfe519564ae001903e5cdd32af0999531ef71'},
    @{name='gpl_3.0.txt';url='https://www.gnu.org/licenses/gpl-3.0.txt'},
    @{name='compiler_rt_21.1.8_license.txt';url='https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-21.1.8/compiler-rt/LICENSE.TXT'}
)
$manifest=@()
foreach($item in $items) {
    $file=Join-Path $Destination $item.name
    if(-not (Test-Path -LiteralPath $file)) { Invoke-WebRequest -Uri $item.url -OutFile $file }
    if($item.sha512 -and (Get-FileHash -LiteralPath $file -Algorithm SHA512).Hash -ne $item.sha512) { throw "Upstream source checksum mismatch: $($item.name)" }
    $manifest+=@{file=$item.name;url=$item.url;sha256=(Get-FileHash -LiteralPath $file).Hash;status='downloaded; provenance/build correspondence review pending'}
    Write-Output "Retrieved $($item.name)"
}
$manifest | ConvertTo-Json | Set-Content (Join-Path $Destination 'download_manifest.json') -Encoding UTF8
