param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationCore
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$fonts=Join-Path (Split-Path $PSScriptRoot) 'shadps4-arm64-main\src\imgui\renderer\fonts'
$records=@()
foreach($file in Get-ChildItem -LiteralPath $fonts -File) {
    $font=[Windows.Media.GlyphTypeface]::new([Uri]$file.FullName)
    $copyright=($font.Copyrights.Values | Select-Object -Unique) -join "`n"
    $license=($font.LicenseDescriptions.Values | Select-Object -Unique) -join "`n"
    $records+=@{file=$file.Name;sha256=(Get-FileHash $file.FullName).Hash;copyright=$copyright;license=$license}
    @($file.Name,'',$copyright,'',$license) | Set-Content (Join-Path $OutputDirectory ($file.BaseName.ToLower()+'_notice.txt')) -Encoding UTF8
}
$records | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputDirectory 'font_metadata.json') -Encoding UTF8
Write-Output 'Font metadata recorded. Noto fonts additionally require the complete OFL 1.1 text.'
