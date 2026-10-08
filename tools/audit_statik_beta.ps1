param([string]$Package = (Join-Path $PSScriptRoot '..\build\statik_local'))
$ErrorActionPreference = 'Stop'
$Package = (Resolve-Path -LiteralPath $Package).Path
$allowed = @('build_manifest.json','launcher.ps1','package_setup.ps1','play_statik.cmd',
    'readme.txt','license.txt','gpl_3.0.txt','third_party_notices.txt','release_audit.txt',
    'pkgtool/LibOrbisPkg.dll','pkgtool/PkgTool.exe','pkgtool/LICENSE.txt','pkgtool/README.md',
    'runtime/shadps4.exe','runtime/user/config.json')
$inventory = @()
$noticeManifest=Join-Path $Package 'notices/notice_manifest.json'
if(Test-Path -LiteralPath $noticeManifest) {
    $allowed += 'notices/notice_manifest.json'
    $notices=@(Get-Content -LiteralPath $noticeManifest -Raw | ConvertFrom-Json)
    $seen=@{}
    foreach($entry in $notices) {
        if($entry.path -notmatch '^(collected|fonts|referenced)/' -or $entry.path -match '(^|/)\.\.(/|$)|[:\\]|(?i)\.(exe|dll|lib|a|pkg|pup|sprx|self|bin|zip|7z)$' -or $seen.ContainsKey($entry.path)) { throw 'Unsafe or duplicate notice manifest path.' }
        $seen[$entry.path]=$true
        $relative='notices/'+$entry.path
        if((Get-FileHash -LiteralPath (Join-Path $Package $relative)).Hash -ne $entry.sha256) { throw "Notice hash mismatch: $relative" }
        $allowed += $relative
    }
}
foreach ($relative in $allowed) {
    if (-not (Test-Path -LiteralPath (Join-Path $Package $relative) -PathType Leaf)) {
        throw "Incomplete distribution: missing $relative"
    }
}
foreach ($file in Get-ChildItem -LiteralPath $Package -Recurse -File -Force) {
    $relative = $file.FullName.Substring($Package.Length + 1).Replace('\','/')
    if ($relative -notin $allowed) { throw "Not a clean distribution: unexpected file $relative. Do not distribute a used runtime, game, module, save or SDK tree." }
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked file forbidden: $relative" }
    $inventory += [pscustomobject]@{path=$relative; bytes=$file.Length; sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
}
foreach ($dir in Get-ChildItem -LiteralPath $Package -Recurse -Directory -Force) {
    if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked directories forbidden.' }
}
$manifest=Get-Content (Join-Path $Package 'build_manifest.json') -Raw | ConvertFrom-Json
$exeHash=(Get-FileHash (Join-Path $Package 'runtime/shadps4.exe')).Hash
if ($manifest.executable_sha256 -ne $exeHash) { throw 'Executable differs from the build manifest.' }
$config=Get-Content (Join-Path $Package 'runtime/user/config.json') -Raw | ConvertFrom-Json
foreach ($key in @('addon_install_dir','font_dir','home_dir','sys_modules_dir','shadnet_server')) {
    if ($config.General.$key) { throw "Machine-specific config field: $key" }
}
if ($config.General.install_dirs.Count -or $config.Input.default_controller_id) { throw 'Personal game/controller settings found.' }
if ($config.Log.enable -or $config.Log.sync -or $config.GPU.dump_shaders -or $config.Debug.debug_dump -or $config.Debug.shader_collect) { throw 'Diagnostics are enabled in default settings.' }
foreach ($key in @('renderdoc_enabled','vkcrash_diagnostic_enabled','vkguest_markers','vkhost_markers','vkvalidation_core_enabled','vkvalidation_enabled','vkvalidation_gpu_enabled','vkvalidation_sync_enabled')) {
    if ($config.Vulkan.$key) { throw "Diagnostic option enabled: $key" }
}
$inventory
Write-Warning 'Content allowlist passed. This is NOT license clearance: see release_audit.txt.'
