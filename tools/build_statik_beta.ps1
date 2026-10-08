param([string]$Destination = (Join-Path $PSScriptRoot '..\build\statik_local'),
    [string]$EmulatorPath = (Join-Path $PSScriptRoot '..\build\pcvr_release\shadps4.exe'),
    [string]$PkgToolDirectory = (Join-Path $PSScriptRoot 'pkgtool'),
    [string]$NoticeDirectory = '')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$Destination = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $Destination) { throw 'Destination already exists. Choose a new folder; existing saves and settings will not be overwritten.' }
$exe = [IO.Path]::GetFullPath($EmulatorPath)
$configSource = Join-Path $repo 'statik_beta\default_config.json'
if (-not (Test-Path $exe)) { throw 'Build the tested Release emulator first.' }
$cache = Get-Content (Join-Path (Split-Path $exe) 'CMakeCache.txt') -Raw
if ($cache -notmatch 'CMAKE_BUILD_TYPE:STRING=Release') { throw 'Expected a Release build.' }
$config = Get-Content $configSource -Raw | ConvertFrom-Json
foreach ($name in @('PkgTool.exe','LibOrbisPkg.dll','LICENSE.txt','README.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PkgToolDirectory $name))) { throw "Extractor dependency missing: $name. Supply -PkgToolDirectory from the upstream 0.2.231 package." }
}
$snapshotPath=Join-Path $repo 'snapshot_status.json'
if (Test-Path $snapshotPath) {
    $snapshot=Get-Content $snapshotPath -Raw | ConvertFrom-Json
    $upstream=$snapshot.upstream
    $revision=if($snapshot.source_revision) { $snapshot.source_revision } else { $upstream }
    $dirty=$snapshot.source_dirty -eq $true
}
else {
    $revision=(& git -c "safe.directory=$($repo.Replace('\','/'))" -C $repo rev-parse HEAD)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot establish source base revision.' }
    $upstream=(& git -c "safe.directory=$($repo.Replace('\','/'))" -C $repo merge-base origin/main HEAD)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot establish upstream base revision.' }
    $dirty=@(& git -c "safe.directory=$($repo.Replace('\','/'))" -C $repo status --porcelain).Count -ne 0
}
foreach ($key in @('addon_install_dir','font_dir','home_dir','sys_modules_dir','shadnet_server')) { $config.General.$key = '' }
$config.General.install_dirs = @()
$config.Input.default_controller_id = ''; $config.Input.camera_id = -1
foreach ($key in @('openal_main_output_device','openal_mic_device','openal_padSpk_output_device','sdl_main_output_device','sdl_mic_device','sdl_padSpk_output_device')) { $config.Audio.$key = 'Default Device' }
$config.Log.enable = $false; $config.Log.sync = $false; $config.Log.filter = '*:Critical'
$config.Debug.debug_dump = $false; $config.Debug.shader_collect = $false
$config.GPU.dump_shaders = $false; $config.GPU.copy_gpu_buffers = $false; $config.GPU.full_screen = $false
foreach ($key in @('renderdoc_enabled','vkcrash_diagnostic_enabled','vkguest_markers','vkhost_markers','vkvalidation_core_enabled','vkvalidation_enabled','vkvalidation_gpu_enabled','vkvalidation_sync_enabled')) { $config.Vulkan.$key = $false }
[void][IO.Directory]::CreateDirectory((Join-Path $Destination 'runtime\user'))
# Explicit allowlist: never copy a runtime/user directory or any games or modules.
foreach ($name in @('play_statik.cmd','launcher.ps1','package_setup.ps1','readme.txt')) { Copy-Item (Join-Path $repo "statik_beta\$name") (Join-Path $Destination $name) }
[void][IO.Directory]::CreateDirectory((Join-Path $Destination 'pkgtool'))
foreach ($name in @('PkgTool.exe','LibOrbisPkg.dll','LICENSE.txt','README.md')) { Copy-Item (Join-Path $PkgToolDirectory $name) (Join-Path $Destination "pkgtool\$name") }
Copy-Item $exe (Join-Path $Destination 'runtime\shadps4.exe')
Copy-Item (Join-Path $repo 'LICENSE') (Join-Path $Destination 'license.txt')
foreach ($name in @('third_party_notices.txt','release_audit.txt','gpl_3.0.txt')) { Copy-Item (Join-Path $repo "statik_beta\$name") (Join-Path $Destination $name) }
$config | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Destination 'runtime\user\config.json') -Encoding UTF8
if ($NoticeDirectory) {
    $noticeManifest=Join-Path $NoticeDirectory 'notice_manifest.json'
    $notices=@(Get-Content -LiteralPath $noticeManifest -Raw | ConvertFrom-Json)
    foreach($entry in $notices) {
        if($entry.path -notmatch '^(collected|fonts|referenced)/' -or $entry.path -match '(^|/)\.\.(/|$)|[:\\]|(?i)\.(exe|dll|lib|a|pkg|pup|sprx|self|bin|zip|7z)$') { throw 'Unsafe notice manifest path.' }
        $source=Join-Path $NoticeDirectory $entry.path
        if((Get-FileHash -LiteralPath $source).Hash -ne $entry.sha256) { throw "Notice hash mismatch: $($entry.path)" }
        $target=Join-Path (Join-Path $Destination 'notices') $entry.path
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        Copy-Item -LiteralPath $source -Destination $target
    }
    Copy-Item -LiteralPath $noticeManifest -Destination (Join-Path $Destination 'notices/notice_manifest.json')
}
@{
    status = 'local staging; distribution source/license audit pending'
    executable_sha256 = (Get-FileHash $exe -Algorithm SHA256).Hash
    upstream_base = $upstream
    source_revision = $revision
    source_dirty = $dirty
    built_at = (Get-Date).ToString('o')
} | ConvertTo-Json | Set-Content (Join-Path $Destination 'build_manifest.json') -Encoding UTF8
Write-Output "Staged beta: $Destination"
& (Join-Path $PSScriptRoot 'audit_statik_beta.ps1') -Package $Destination
