param([Parameter(Mandatory=$true)][string]$LlvmDirectory,
    [Parameter(Mandatory=$true)][string]$BuildDirectory)
$ErrorActionPreference='Stop'
$LlvmDirectory=[IO.Path]::GetFullPath($LlvmDirectory)
$BuildDirectory=[IO.Path]::GetFullPath($BuildDirectory)
$repo=Split-Path $PSScriptRoot
& (Join-Path $PSScriptRoot 'build_pcvr_release.ps1') -LlvmDirectory $LlvmDirectory -BuildDirectory $BuildDirectory -ConfigureOnly
$tests=@('clear_rect','unbound_buffer','gpu_failure_capture','overlay_layout','reprojection_flip',
    'ctype_table','eye_layout','tracker_init_legacy','allocation_trace','allocation_trace_windows','one_shot_probe','guest_file_read',
    'spectator_view','headset_fov_cache','openxr_view','stick_finger','pad_gestures','pad_source','console_language','known_title_builds')
foreach($test in $tests) {
    $exe=Join-Path $BuildDirectory ($test+'_test.exe')
    & (Join-Path $LlvmDirectory 'clang-cl.exe') /nologo /O2 /std:c++latest /EHsc "/I$repo\shadps4-arm64-main\src" `
        "/I$repo\shadps4-arm64-main\externals\json\include" "/I$repo\shadps4-arm64-main\externals\openxr-sdk\include" `
        "$PSScriptRoot\tests\${test}_test.cpp" "/Fe$exe" "/Fo$BuildDirectory\${test}_test.obj"
    if($LASTEXITCODE -ne 0) { throw "Compile failed: $test" }
    & $exe
    if($LASTEXITCODE -ne 0) { throw "Test failed: $test" }
    Write-Output "PASS $test"
}
foreach($test in @('statik_launcher','statik_package','statik_package_cancel','statik_launcher_layout')) {
    & "$PSScriptRoot\tests\${test}_test.ps1"
}
