param([string]$Package='')
$ErrorActionPreference='Stop'
$tools=Split-Path $PSScriptRoot
$temp=Join-Path ([IO.Path]::GetTempPath()) ('statik_distribution_'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
    $rejected=$false
    try { & (Join-Path $tools 'audit_statik_beta.ps1') -Package $temp | Out-Null } catch {
        if ($_.Exception.Message -notlike 'Incomplete distribution:*') { throw }
        $rejected=$true
    }
    if (-not $rejected) { throw 'Empty distribution incorrectly passed.' }
    Write-Output 'Empty/incomplete distribution is correctly rejected.'
    if($Package) {
        $Package=(Resolve-Path -LiteralPath $Package).Path
        foreach($item in Get-ChildItem -LiteralPath $Package -Force) { Copy-Item -LiteralPath $item.FullName -Destination $temp -Recurse }
        function Expect-Rejection([string]$pattern) {
            $message=''
            try { & (Join-Path $tools 'audit_statik_beta.ps1') -Package $temp | Out-Null } catch { $message=$_.Exception.Message }
            if($message -notlike $pattern) { throw "Expected rejection '$pattern', got '$message'" }
        }
        & (Join-Path $tools 'audit_statik_beta.ps1') -Package $temp | Out-Null
        $extra=Join-Path $temp 'unexpected.sprx'
        [IO.File]::WriteAllText($extra,'test fixture, not a module')
        Expect-Rejection 'Not a clean distribution:*'
        [IO.File]::Delete($extra)
        $configPath=Join-Path $temp 'runtime/user/config.json'
        $config=Get-Content $configPath -Raw | ConvertFrom-Json
        $config.Log.enable=$true
        $config | ConvertTo-Json -Depth 12 | Set-Content $configPath -Encoding UTF8
        Expect-Rejection 'Diagnostics are enabled*'
        $config.Log.enable=$false; $config.General.home_dir='C:\private_test_fixture'
        $config | ConvertTo-Json -Depth 12 | Set-Content $configPath -Encoding UTF8
        Expect-Rejection 'Machine-specific config field:*'
        Copy-Item (Join-Path $Package 'runtime/user/config.json') $configPath
        $noticePath=Join-Path $temp 'notices/notice_manifest.json'
        if(Test-Path -LiteralPath $noticePath) {
            $notices=@(Get-Content $noticePath -Raw | ConvertFrom-Json)
            $notices[0].sha256='invalid-test-hash'
            $notices | ConvertTo-Json | Set-Content $noticePath -Encoding UTF8
            Expect-Rejection 'Notice hash mismatch:*'
            $notices[0].path='collected/../../outside.txt'
            $notices | ConvertTo-Json | Set-Content $noticePath -Encoding UTF8
            Expect-Rejection 'Unsafe or duplicate notice manifest path.'
            $notices[0].path='collected/module.sprx'
            $notices | ConvertTo-Json | Set-Content $noticePath -Encoding UTF8
            Expect-Rejection 'Unsafe or duplicate notice manifest path.'
            Copy-Item (Join-Path $Package 'notices/notice_manifest.json') $noticePath
            Write-Output 'Notice hash mismatch, path traversal and forbidden binary entry rejected.'
        }
        $manifestPath=Join-Path $temp 'build_manifest.json'
        $manifest=Get-Content $manifestPath -Raw | ConvertFrom-Json
        $manifest.executable_sha256='invalid-test-hash'
        $manifest | ConvertTo-Json | Set-Content $manifestPath -Encoding UTF8
        Expect-Rejection 'Executable differs*'
        Write-Output 'Unexpected files, enabled diagnostics, personal paths and executable mismatch rejected.'
    }
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    $expectedParent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if([IO.Path]::GetDirectoryName($resolved) -ne $expectedParent -or [IO.Path]::GetFileName($resolved) -notlike 'statik_distribution_*') { throw 'Unsafe temporary cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
