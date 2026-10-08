# Statik PC VR beta. GPL-2.0-or-later.
# Windows Forms presentation inspired by AstroQuest pc-vr/launch.ps1 (bigmak94).
param([switch]$CheckOnly, [string]$PreviewPath = '')
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'package_setup.ps1')
$settingsPath = Join-Path $root 'settings.json'
$settings = @{ game = ''; mode = 'Headset (OpenXR)'; diagnostics = $false }
if (Test-Path $settingsPath) {
    try {
        $saved = Get-Content $settingsPath -Raw | ConvertFrom-Json
        $settings.game = [string]$saved.game
        if ($saved.mode -in @('Headset (OpenXR)', 'Desktop preview')) { $settings.mode = $saved.mode }
        $settings.diagnostics = $saved.diagnostics -eq $true
    } catch { Write-Warning 'Settings could not be read; using defaults.' }
}
function Get-GameError([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return 'Choose the eboot.bin from your extracted Statik game.' }
    if ([IO.Path]::GetFileName($path) -ne 'eboot.bin') { return 'Choose eboot.bin, not a package or another file.' }
    $sfo = Join-Path (Split-Path $path) 'sce_sys\param.sfo'
    if (-not (Test-Path -LiteralPath $sfo)) { return 'The game folder is missing sce_sys\param.sfo.' }
    try { $metadata = Read-StatikSfo $sfo } catch { return 'The game metadata is invalid or unreadable.' }
    if ($metadata.TITLE_ID -ne 'CUSA06929') { return 'This beta is tested with Statik CUSA06929 only. Please select that game version.' }
    if ($metadata.CATEGORY -ne 'gd') { return 'Select the base game, not an extracted update or add-on.' }
    return ''
}
function Get-OpenXRRuntime {
    $key = Get-ItemProperty 'HKLM:\SOFTWARE\Khronos\OpenXR\1' -ErrorAction SilentlyContinue
    if ($key -and $key.ActiveRuntime -and (Test-Path -LiteralPath $key.ActiveRuntime)) { return [string]$key.ActiveRuntime }
    return ''
}
function Get-RuntimeMissing {
    @('vcruntime140.dll','vcruntime140_1.dll','msvcp140.dll','msvcp140_2.dll','msvcp140_atomic_wait.dll') |
        Where-Object { -not (Test-Path (Join-Path ([Environment]::SystemDirectory) $_)) }
}
if ($CheckOnly) {
    [pscustomobject]@{ EmulatorPresent = Test-Path (Join-Path $root 'runtime\shadps4.exe'); OpenXR = Get-OpenXRRuntime; MissingRuntime = @(Get-RuntimeMissing); GameError = Get-GameError $settings.game }
    return
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
function Tell([string]$message) { [void][Windows.Forms.MessageBox]::Show($form, $message, 'Statik PC VR beta') }
function Pick-File([string]$title, [string]$filter) {
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = $title; $dialog.Filter = $filter
    try { if ($dialog.ShowDialog($form) -eq 'OK') { return $dialog.FileName } } finally { $dialog.Dispose() }
    return ''
}
$form = New-Object Windows.Forms.Form
$form.Text = 'Statik PC VR beta'
$form.ClientSize = New-Object Drawing.Size(650, 470)
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.AutoScaleMode = 'Dpi'
function Label([string]$text, [int]$y, [int]$height, [bool]$bold = $false) {
    $control = New-Object Windows.Forms.Label
    $control.Text = $text; $control.SetBounds(20,$y,610,$height)
    if ($bold) { $control.Font = New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold) }
    $form.Controls.Add($control)
}
Label 'STATIK - Institute of Retention | PC VR beta' 18 30 $true
Label 'An unofficial compatibility build based on AstroQuest and shadPS4.' 51 26
Label 'Your game' 89 24 $true
$game = New-Object Windows.Forms.TextBox
$game.SetBounds(20,118,510,27); $game.Text = $settings.game
$form.Controls.Add($game)
$browse = New-Object Windows.Forms.Button
$browse.Text = 'Browse...'; $browse.SetBounds(540,116,90,30)
$browse.Add_Click({ $file = Pick-File 'Select Statik game or package' 'Statik game or package|eboot.bin;*.pkg'; if ($file) { $game.Text = $file } })
$form.Controls.Add($browse)
Label 'Select eboot.bin or a base-game .pkg for CUSA06929. Packages are unpacked once into this beta folder; the original is kept.' 151 43
Label 'Play mode' 203 24 $true
$mode = New-Object Windows.Forms.ComboBox
$mode.DropDownStyle = 'DropDownList'; $mode.SetBounds(20,232,250,28)
[void]$mode.Items.AddRange(@('Headset (OpenXR)','Desktop preview'))
$mode.SelectedItem = $settings.mode; $form.Controls.Add($mode)
$xr = Get-OpenXRRuntime
$runtimeText = if ($xr) { 'OpenXR runtime detected. Connect your headset and start its PC VR connection before pressing Play.' } else { 'No active OpenXR runtime found. Set up your headset software first, or select Desktop preview.' }
Label $runtimeText 270 48
Label 'Uses the tested Statik stereo and tracking settings. Adjust streaming quality in your headset software. Desktop preview has no live headset tracking.' 324 48
$diagnostics = New-Object Windows.Forms.CheckBox
$diagnostics.Text = 'Enable troubleshooting logs (off for normal play)'
$diagnostics.SetBounds(20,384,580,25); $diagnostics.Checked = $settings.diagnostics
$form.Controls.Add($diagnostics)
$play = New-Object Windows.Forms.Button
$play.Text = 'Play'; $play.SetBounds(424,426,98,30)
$quit = New-Object Windows.Forms.Button
$quit.Text = 'Quit'; $quit.SetBounds(532,426,98,30)
$quit.Add_Click({ $form.Close() })
$form.Controls.AddRange(@($play,$quit)); $form.AcceptButton = $play; $form.CancelButton = $quit
$play.Add_Click({
    try {
        if ([IO.Path]::GetExtension($game.Text) -ieq '.pkg') {
            $null = Get-StatikPackageInfo $game.Text
            $answer = [Windows.Forms.MessageBox]::Show($form,'Unpack this package into the beta games folder? This can take several minutes and several GB. Your original package will be kept.','Install Statik','YesNo')
            if ($answer -ne 'Yes') { return }
            $runner = {
                param($tool,$arguments,$work)
                $progress = New-Object Windows.Forms.Form
                $progress.Text='Unpacking Statik'; $progress.ClientSize=New-Object Drawing.Size(460,130)
                $progress.StartPosition='CenterParent'; $progress.ControlBox=$false
                $label=New-Object Windows.Forms.Label; $label.Text='Unpacking game files. Please wait...'; $label.SetBounds(16,16,420,24)
                $bar=New-Object Windows.Forms.ProgressBar; $bar.Style='Marquee'; $bar.SetBounds(16,48,420,22)
                $cancel=New-Object Windows.Forms.Button; $cancel.Text='Cancel'; $cancel.SetBounds(340,88,96,28)
                $cancel.Add_Click({ $progress.Tag='cancel' })
                $progress.Controls.AddRange(@($label,$bar,$cancel))
                $process=$null
                try {
                    $process=Start-Process -FilePath $tool -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput (Join-Path $work 'extract.log') -RedirectStandardError (Join-Path $work 'error.log') -PassThru
                    $null=$process.Handle
                    $form.Enabled=$false; $progress.Show($form)
                    while (-not $process.HasExited) {
                        [Windows.Forms.Application]::DoEvents()
                        if ($progress.Tag -eq 'cancel') { $process.Kill(); $process.WaitForExit(); throw 'Cancelled by user.' }
                        Start-Sleep -Milliseconds 100
                    }
                    if ($process.ExitCode -ne 0) { throw "PkgTool exited with code $($process.ExitCode). See error.log; encrypted retail packages are not supported." }
                } finally {
                    if ($process -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
                    $progress.Dispose(); $form.Enabled=$true
                }
            }
            $game.Text = Install-StatikPackage $game.Text $root (Join-Path $root 'pkgtool\PkgTool.exe') $runner
        }
        $gameError = Get-GameError $game.Text
        if ($gameError) { Tell $gameError; return }
        $exe = Join-Path $root 'runtime\shadps4.exe'
        if (-not (Test-Path $exe)) { Tell 'The emulator is missing. Extract the complete beta package into a writable folder.'; return }
        if (Get-Process shadps4 -ErrorAction SilentlyContinue) { Tell 'Close the running shadPS4 game before starting another instance.'; return }
        if (@(Get-RuntimeMissing).Count) { Tell 'Install the Microsoft Visual C++ 2015-2022 x64 Redistributable, then try again. The download link is in readme.txt.'; return }
        $headset = $mode.SelectedIndex -eq 0
        if ($headset -and -not (Get-OpenXRRuntime)) { Tell 'No active OpenXR runtime was found. Enable your headset software as the OpenXR runtime first.'; return }
        $moduleDir = Join-Path $root 'runtime\user\custom_modules\CUSA06929'
        $module = Join-Path $moduleDir 'libSceJson2.sprx'
        if (-not (Test-Path $module)) {
            Tell 'This build requires your own decrypted libSceJson2.sprx system module. Select it in the next window. It will be copied into this beta folder.'
            $source = Pick-File 'Select your libSceJson2.sprx' 'JSON system module|libSceJson2.sprx'
            if (-not $source) { return }
            $header = [IO.File]::ReadAllBytes($source)
            if ($header.Length -lt 4 -or $header[0] -ne 127 -or $header[1] -ne 69 -or $header[2] -ne 76 -or $header[3] -ne 70) { Tell 'This is not a decrypted ELF module. Please supply a compatible decrypted copy.'; return }
            [void][IO.Directory]::CreateDirectory($moduleDir)
            Copy-Item -LiteralPath $source -Destination $module
        }
        @{game=$game.Text;mode=[string]$mode.SelectedItem;diagnostics=$diagnostics.Checked} | ConvertTo-Json | Set-Content $settingsPath -Encoding UTF8
        $configPath = Join-Path $root 'runtime\user\config.json'
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $config.Log.enable = $diagnostics.Checked; $config.Log.sync = $false
        $config.Log.filter = if ($diagnostics.Checked) { '*:Warning Core.Vr:Info' } else { '*:Critical' }
        $config | ConvertTo-Json -Depth 12 | Set-Content $configPath -Encoding UTF8
        # Do not inherit experimental emulator options from the launching shell.
        Get-ChildItem Env: | Where-Object Name -Like 'SHADPS4_*' | ForEach-Object { Remove-Item ('Env:' + $_.Name) }
        $env:SHADPS4_VR='1'; $env:SHADPS4_JSON='0'
        $env:SHADPS4_OPENXR = if ($headset) {'1'} else {'0'}
        $env:SHADPS4_VR_DEMO = if ($headset) {'0'} else {'1'}
        $env:SHADPS4_XR_PAUSE = if ($headset) {'1'} else {'0'}
        if ($headset) { $env:SHADPS4_XR_HEAD='1'; $env:SHADPS4_XR_HANDS='1'; $env:SHADPS4_XR_GRIPS='1'; $env:SHADPS4_XR_CONTROLLERS='1' }
        $form.Hide()
        try {
            $process = Start-Process -FilePath $exe -ArgumentList @('-g', ('"' + $game.Text + '"')) -WorkingDirectory (Join-Path $root 'runtime') -WindowStyle Hidden -RedirectStandardOutput (Join-Path $root 'last_run.log') -RedirectStandardError (Join-Path $root 'last_error.log') -PassThru
            $null = $process.Handle
            while (-not $process.HasExited) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
            $exitCode = $process.ExitCode
        } finally { $form.Show(); $form.Activate() }
        if ($exitCode -ne 0) { Tell "Statik exited with code $exitCode. Enable troubleshooting logs and include last_run.log, last_error.log and runtime\user\log when reporting a problem. Do not share your game, modules or saves." }
    } catch { Tell ("Could not start Statik: " + $_.Exception.Message) }
})
try {
    if ($PreviewPath) {
        $form.Show(); [Windows.Forms.Application]::DoEvents()
        $bitmap = New-Object Drawing.Bitmap($form.Width,$form.Height)
        try { $form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height))); $bitmap.Save($PreviewPath) } finally { $bitmap.Dispose() }
    } else { [void]$form.ShowDialog() }
} finally { $form.Dispose() }
