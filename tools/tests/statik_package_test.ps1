$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\..\pc-vr\package_setup.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('statik_pkg_'+[Guid]::NewGuid().ToString('N')+'.pkg')
try {
    $header=New-Object byte[] 128
    $header[0]=127; $header[1]=67; $header[2]=78; $header[3]=84
    [Text.Encoding]::ASCII.GetBytes('EP2462-CUSA06929_00-STATIKSIEE000001').CopyTo($header,64)
    [IO.File]::WriteAllBytes($temp,$header)
    if (-not (Get-StatikPackageInfo $temp)) { throw 'Base package rejected.' }
    foreach ($case in @(@(0x78,0x20),@(0x78,0x40),@(0x79,0x10),@(0x79,0x20))) {
        $header[0x78]=0; $header[0x79]=0; $header[$case[0]]=$case[1]
        [IO.File]::WriteAllBytes($temp,$header)
        $rejected=$false
        try { $null=Get-StatikPackageInfo $temp } catch { $rejected=$true }
        if (-not $rejected) { throw 'Update package accepted.' }
    }
    $header[0x78]=0; $header[0x79]=0; $header[71]=88
    [IO.File]::WriteAllBytes($temp,$header)
    $rejected=$false
    try { $null=Get-StatikPackageInfo $temp } catch { $rejected=$true }
    if (-not $rejected) { throw 'Wrong title accepted.' }
    Write-Output 'Base, update/PATCHGO and wrong-title package checks passed.'
} finally { [IO.File]::Delete($temp) }
