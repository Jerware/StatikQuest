$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\..\statik_beta\package_setup.ps1')
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$root=Join-Path $base ('spc_'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try {
    $pkg=Join-Path $root 'synthetic.pkg'
    $header=New-Object byte[] 128
    $header[0]=127; $header[1]=67; $header[2]=78; $header[3]=84
    [Text.Encoding]::ASCII.GetBytes('EP2462-CUSA06929_00-STATIKSIEE000001').CopyTo($header,64)
    [IO.File]::WriteAllBytes($pkg,$header)
    $hash=(Get-FileHash $pkg).Hash
    # The runner is the launcher's extraction boundary. Simulate cancellation
    # after creating partial output; no game data or executable is involved.
    $runner={ param($tool,$arguments,$work)
        [IO.File]::WriteAllText((Join-Path $work 'partial.txt'),'synthetic partial output')
        throw 'Cancelled by user.'
    }
    $cancelled=$false
    try { Install-StatikPackage $pkg $root $PSCommandPath $runner | Out-Null }
    catch {
        if($_.Exception.Message -notlike '*Cancelled by user.*Partial files and logs are retained*') { throw }
        $cancelled=$true
    }
    if(-not $cancelled) { throw 'Cancellation did not propagate.' }
    if(Test-Path (Join-Path $root 'games\cusa06929')) { throw 'Cancelled install was published.' }
    $partial=@(Get-ChildItem (Join-Path $root 'games') -Directory)
    if($partial.Count -ne 1 -or -not(Test-Path (Join-Path $partial[0].FullName 'partial.txt'))) { throw 'Partial output was not retained.' }
    if((Get-FileHash $pkg).Hash -ne $hash) { throw 'Original package changed.' }
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'games\cusa06929'))
    $protected=$false
    try { Install-StatikPackage $pkg $root $PSCommandPath { throw 'Runner must not execute.' } | Out-Null }
    catch { if($_.Exception.Message -notlike 'An installation already exists*') { throw }; $protected=$true }
    if(-not $protected) { throw 'Existing installation was not protected.' }
    Write-Output 'PASS cancellation boundary: partial retained, original unchanged, no final install; existing installation protected.'
    Write-Output 'This does not simulate clicking Cancel or prove child-process termination in the GUI.'
} finally {
    $resolved=[IO.Path]::GetFullPath($root)
    if([IO.Path]::GetDirectoryName($resolved).TrimEnd('\') -ne $base.TrimEnd('\') -or [IO.Path]::GetFileName($resolved) -notmatch '^spc_[0-9a-f]{32}$') { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
