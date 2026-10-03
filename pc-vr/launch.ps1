# Starts ASTRO BOT Rescue Mission in the emulator for a headset connected to this PC (Virtual
# Desktop, or anything else with an OpenXR runtime), and tells what is going on while it runs.
# Started by "Play Astro Bot VR.bat"; settings are in settings.txt next to this file, and the
# main ones can be chosen in a small window before the game starts.
param([string]$SettingsFile = "", [switch]$NoMenu)

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
Set-Location $here
if ($SettingsFile -eq "") { $SettingsFile = Join-Path $here "settings.txt" }

function Say([string]$text, [string]$color = "Gray") { Write-Host $text -ForegroundColor $color }

# --- settings -------------------------------------------------------------------------------
function Read-Settings {
    $script:settings = [ordered]@{}
    $script:extraEnv = @()
    if (Test-Path $SettingsFile) {
        foreach ($line in Get-Content $SettingsFile) {
            $line = $line.Trim()
            if ($line -eq "" -or $line.StartsWith("#")) { continue }
            $at = $line.IndexOf("=")
            if ($at -lt 1) { continue }
            $key = $line.Substring(0, $at).Trim().ToLower()
            $value = $line.Substring($at + 1).Trim()
            if ($key -eq "env") { $script:extraEnv += $value } else { $script:settings[$key] = $value }
        }
    }
}
function Setting([string]$key, [string]$default = "") {
    if ($settings.Contains($key)) { return $settings[$key] }
    return $default
}
# Writes key=value into the settings file: in place of the line that sets it, or at the end.
function Save-Setting([string]$key, [string]$value) {
    $lines = @()
    if (Test-Path $SettingsFile) { $lines = @(Get-Content $SettingsFile) }
    $done = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ("^\s*" + [regex]::Escape($key) + "\s*=")) {
            $lines[$i] = "$key=$value"
            $done = $true
        }
    }
    if (-not $done) { $lines += "$key=$value" }
    Set-Content -Path $SettingsFile -Value $lines -Encoding UTF8
}
Read-Settings

# The sizes an eye can be drawn at: the console's largest (1440x1536, what a PlayStation 4 Pro
# draws) and larger, all the same shape.
$widths = @(1440, 1800, 2160, 2520, 2880, 3240, 3600)
function EyeHeight([int]$width) { return [int]([math]::Round(1536.0 * $width / 1440 / 8) * 8) }
$caps = @(120, 90, 72, 60, 45, 40, 36, 30)

# --- the window -------------------------------------------------------------------------------
function Show-Menu {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Astro Bot VR"
    $form.ClientSize = New-Object System.Drawing.Size(560, 452)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

    $y = 14
    $title = New-Object System.Windows.Forms.Label
    $title.Text = "ASTRO BOT Rescue Mission - PC VR"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $title.SetBounds(16, $y, 520, 26)
    $form.Controls.Add($title)
    $y += 40

    # Resolution.
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Resolution of each eye"
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $label.SetBounds(16, $y, 520, 20)
    $form.Controls.Add($label)
    $y += 22
    $resolution = New-Object System.Windows.Forms.TrackBar
    $resolution.Minimum = 0
    $resolution.Maximum = $widths.Count - 1
    $resolution.TickFrequency = 1
    $resolution.LargeChange = 1
    $resolution.SetBounds(12, $y, 530, 40)
    $current = [int](Setting "resolution" "2880")
    $index = [array]::IndexOf($widths, $current)
    if ($index -lt 0) { $index = 4 }
    $resolution.Value = $index
    $form.Controls.Add($resolution)
    $y += 42
    $resolutionText = New-Object System.Windows.Forms.Label
    $resolutionText.SetBounds(16, $y, 530, 38)
    $form.Controls.Add($resolutionText)
    $update = {
        $w = $widths[$resolution.Value]
        $h = EyeHeight $w
        $times = ($w * $h) / (1440.0 * 1536.0)
        $what = if ($w -eq 1440) { "the console's own, as a PlayStation 4 Pro draws it" } else { "{0:N2} times the pixels of the console" -f $times }
        $resolutionText.Text = "$w x $h pixels an eye: $what. The game draws smaller by itself when the graphics card cannot keep up."
    }
    $resolution.Add_ValueChanged($update)
    & $update
    $y += 46

    # Frame rate.
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Frames a second, at most"
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $label.SetBounds(16, $y, 520, 20)
    $form.Controls.Add($label)
    $y += 24
    $fps = New-Object System.Windows.Forms.ComboBox
    $fps.DropDownStyle = "DropDownList"
    foreach ($cap in $caps) {
        $text = "$cap"
        if ($cap -eq 60) { $text = "60 (the console's own)" }
        [void]$fps.Items.Add($text)
    }
    $fps.SetBounds(16, $y, 200, 26)
    $index = [array]::IndexOf($caps, [int](Setting "fps" "60"))
    if ($index -lt 0) { $index = 3 }
    $fps.SelectedIndex = $index
    $form.Controls.Add($fps)
    $y += 32
    $fpsText = New-Object System.Windows.Forms.Label
    $fpsText.Text = "A frame lasts a whole number of the headset's refreshes, so the headset's refresh rate decides what is possible: at 120 Hz 120, 60, 40 or 30 frames a second, at 90 Hz 90, 45 or 30, at 72 Hz 72 or 36. Virtual Desktop sets the refresh rate (Settings > Streaming > Frame rate): choose 120 for 60 frames a second."
    $fpsText.SetBounds(16, $y, 530, 84)
    $form.Controls.Add($fpsText)
    $y += 88

    # Field of view.
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Field of view"
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $label.SetBounds(16, $y, 520, 20)
    $form.Controls.Add($label)
    $y += 22
    $fov = New-Object System.Windows.Forms.TrackBar
    $fov.Minimum = 14
    $fov.Maximum = 20
    $fov.TickFrequency = 1
    $fov.LargeChange = 1
    $fov.SetBounds(12, $y, 300, 40)
    $fov.Value = [math]::Max(14, [math]::Min(20, [int]([int](Setting "fov" "100") / 5)))
    $form.Controls.Add($fov)
    $fovText = New-Object System.Windows.Forms.Label
    $fovText.SetBounds(316, $y + 4, 230, 40)
    $form.Controls.Add($fovText)
    $ofPsvr = (Setting "fov_of" "headset") -eq "psvr"
    $updateFov = {
        $percent = $fov.Value * 5
        if ($percent -eq 100) {
            $fovText.Text = $(if ($ofPsvr) { "100%: PlayStation VR's own" } else { "100%: all that the headset shows" })
        } else {
            $fovText.Text = "$percent% of it: sharper, with a dark border"
        }
    }
    $fov.Add_ValueChanged($updateFov)
    & $updateFov
    $y += 46

    $again = New-Object System.Windows.Forms.CheckBox
    $again.Text = "Show this window at every start"
    $again.Checked = (Setting "menu" "1") -ne "0"
    $again.SetBounds(16, $y, 300, 24)
    $form.Controls.Add($again)

    $play = New-Object System.Windows.Forms.Button
    $play.Text = "Play"
    $play.SetBounds(360, $y - 2, 88, 30)
    $play.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($play)
    $form.AcceptButton = $play
    $quit = New-Object System.Windows.Forms.Button
    $quit.Text = "Quit"
    $quit.SetBounds(456, $y - 2, 88, 30)
    $quit.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($quit)
    $form.CancelButton = $quit

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $false }
    Save-Setting "resolution" ($widths[$resolution.Value])
    Save-Setting "fps" ($caps[$fps.SelectedIndex])
    Save-Setting "fov" ($fov.Value * 5)
    Save-Setting "menu" ($(if ($again.Checked) { "1" } else { "0" }))
    Read-Settings
    return $true
}

if (-not $NoMenu -and (Setting "menu" "1") -ne "0") {
    if (-not (Show-Menu)) { exit 0 }
}

$game = Setting "game" (Join-Path $root "games\CUSA12392\eboot.bin")
if (-not (Test-Path $game)) {
    Say "The game was not found at $game" "Red"
    Say "Put the extracted game there, or name its eboot.bin with game=... in settings.txt."
    Read-Host "Press Enter to close"
    exit 1
}
$emulator = Join-Path $here "shadps4.exe"
if (-not (Test-Path $emulator)) {
    Say "shadps4.exe is missing from $here (run tools/make-pc-vr.sh)" "Red"
    Read-Host "Press Enter to close"
    exit 1
}

# What the settings mean to the emulator.
# resolution: the width of an eye (1440 the console's; larger ones are the game's sizes grown,
# with the memory that takes). game: the console's sizes, chosen by the game itself.
$resolution = Setting "resolution" "2880"
$dynamic = (Setting "dynamic" "1") -ne "0"
if ($resolution -eq "game") {
    $env:SHADPS4_TITLE_RESOLUTION = "title"
} else {
    $width = 0
    if (-not [int]::TryParse($resolution, [ref]$width)) { $width = 2880 }
    # (The console's other sizes, 816 to 1200, as they were offered before.)
    $smaller = @{ 816 = "3"; 960 = "4"; 1200 = "5" }
    if ($smaller.ContainsKey($width)) {
        $env:SHADPS4_TITLE_RESOLUTION = $smaller[$width]
    } else {
        $width = [math]::Max(1440, [math]::Min(4320, [int]([math]::Round($width / 8) * 8)))
        if ($width -gt 1440) { $env:SHADPS4_TITLE_EYE_WIDTH = "$width" }
        # Left to choose, the emulator draws smaller where the graphics card falls behind.
        if (-not $dynamic) { $env:SHADPS4_TITLE_RESOLUTION = "6" }
    }
}
$env:SHADPS4_VR_SHARPEN = Setting "sharpen" "0.3"
if ((Setting "msaa") -ne "") { $env:SHADPS4_MAX_MSAA = Setting "msaa" }
if ((Setting "antialias" "1") -eq "0") { $env:SHADPS4_RESOLVE_AA = "0" }
if ((Setting "hands" "1") -eq "0") { $env:SHADPS4_XR_HANDS = "0" }
if ((Setting "predict_ms") -ne "") { $env:SHADPS4_XR_PREDICT_MS = Setting "predict_ms" }
if ((Setting "stick_touchpad" "1") -eq "0") { $env:SHADPS4_STICK_TOUCHPAD = "0" }
if ((Setting "surround" "1") -eq "0") { $env:SHADPS4_VIRTUAL_SURROUND = "0" }
if ((Setting "real_time" "1") -eq "0") { $env:SHADPS4_TITLE_TIMESTEP = "0" }
$fovSetting = Setting "fov" "100"
if ($fovSetting -ne "100") { $env:SHADPS4_VR_FOV = $fovSetting }
# fov_of: what fov is a percent of. headset: what the headset being worn shows, all of it at 100
# (the emulator asks the headset as it starts). psvr: a PlayStation VR's, as the game was made.
if ((Setting "fov_of" "headset") -ne "psvr") { $env:SHADPS4_VR_FOV_OF = "headset" }
# fps: the most frames a second. (pace, the older way to say it: refreshes of the headset a
# frame is given, 1 or more.)
$env:SHADPS4_VR_FPS_CAP = Setting "fps" "60"
$pace = Setting "pace" ""
if ($pace -eq "1") { $env:SHADPS4_VR_FASTEST_PACE = "1"; $env:SHADPS4_VR_FPS_CAP = "" } elseif ($pace -ne "" -and $pace -ne "2") { $env:SHADPS4_VR_PACE = $pace }
if ((Setting "headset" "1") -eq "0") { $env:SHADPS4_OPENXR = "0" }
if ((Setting "pause" "1") -eq "0") { $env:SHADPS4_XR_PAUSE = "0" }
if ((Setting "controllers" "1") -eq "0") { $env:SHADPS4_XR_CONTROLLERS = "0" }
if ((Setting "controller_hand" "right") -eq "left") { $env:SHADPS4_XR_PAD_HAND = "left" }
$env:SHADPS4_XR_WAIT = Setting "wait" "60"
foreach ($pair in $extraEnv) {
    $at = $pair.IndexOf("=")
    if ($at -ge 1) { Set-Item -Path ("Env:" + $pair.Substring(0, $at)) -Value $pair.Substring($at + 1) }
}

# --- what is there ----------------------------------------------------------------------------
Say "ASTRO BOT Rescue Mission - PC VR" "Cyan"
if ($env:SHADPS4_TITLE_EYE_WIDTH) {
    Say ("Each eye up to " + $env:SHADPS4_TITLE_EYE_WIDTH + " x " + (EyeHeight ([int]$env:SHADPS4_TITLE_EYE_WIDTH)) + ", at most " + $env:SHADPS4_VR_FPS_CAP + " frames a second.")
}
$runtime = ""
if ($env:XR_RUNTIME_JSON) {
    $runtime = $env:XR_RUNTIME_JSON
} else {
    try { $runtime = (Get-ItemProperty 'HKLM:\SOFTWARE\Khronos\OpenXR\1' -ErrorAction Stop).ActiveRuntime } catch {}
}
if ($runtime -eq "") {
    Say "No OpenXR runtime is set up on this PC: the game will only show on the monitor." "Yellow"
    Say "Virtual Desktop Streamer installs one (Options > OpenXR Runtime: VDXR)."
} else {
    Say "OpenXR runtime: $runtime"
    if ($runtime -match "virtualdesktop") {
        $streamer = Get-Process "VirtualDesktop.Streamer" -ErrorAction SilentlyContinue
        if (-not $streamer) {
            $exe = Join-Path (Split-Path -Parent (Split-Path -Parent $runtime)) "VirtualDesktop.Streamer.exe"
            if (Test-Path $exe) {
                Say "Starting Virtual Desktop Streamer..."
                Start-Process $exe
            } else {
                Say "Virtual Desktop Streamer is not running: start it, then connect from the headset." "Yellow"
            }
        }
    }
}
Say ""
Say "In the headset: connect Virtual Desktop to this PC. The game moves into the headset by itself."
if ($env:SHADPS4_OPENXR -ne "0" -and [int]$env:SHADPS4_XR_WAIT -gt 0) {
    Say ("The game waits up to " + $env:SHADPS4_XR_WAIT + " seconds for the headset before it starts on the monitor.")
}
Say "The DualSense: connect it to THIS PC (USB cable, or Bluetooth paired with the PC). Paired with"
Say "the headset, it reaches the PC through Virtual Desktop without motion sensors or touchpad."
Say "Where it is in the game comes from your hands: hand tracking on in the headset, and in"
Say "Virtual Desktop's settings hand tracking forwarded to the PC."
Say "Hold OPTIONS for a second (or press the PS button) to reset the view."
Say "No gamepad: the headset's own controllers play (A jump, B punch, right stick = touchpad,"
Say "press both sticks in to reset the view)."
Say "Close the game's window to quit."
Say ""

# --- run --------------------------------------------------------------------------------------
$logDir = Join-Path $here "user\log"
$log = Join-Path $logDir "shad_log.txt"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
if (Test-Path $log) { Copy-Item $log (Join-Path $logDir "shad_log.prev.txt") -Force }

# (In this console, with what it prints kept out of the way: a window style given here would
# also be the game window's.)
$process = Start-Process -FilePath $emulator -ArgumentList @("-g", "`"$game`"") -WorkingDirectory $here `
    -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $logDir "console.txt") `
    -RedirectStandardError (Join-Path $logDir "console-errors.txt")
# (Without this the exit code is not to be had later.)
$null = $process.Handle
$position = 0
$shown = @{}
function Show-Log {
    if (-not (Test-Path $log)) { return }
    try {
        $stream = [System.IO.File]::Open($log, 'Open', 'Read', 'ReadWrite')
    } catch { return }
    try {
        if ($stream.Length -lt $script:position) { $script:position = 0 }
        [void]$stream.Seek($script:position, 'Begin')
        $reader = New-Object System.IO.StreamReader($stream)
        while ($true) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            if ($line -match '^\[Core\.Vr\] <(Info|Warning)> \([^)]*\) \S+ (?:\w+: )?(.*)$') {
                $warning = $Matches[1] -eq "Warning"
                $text = $Matches[2]
                # The lines that repeat every few seconds only once in a while.
                if ($text -match '^(The title (has|now takes) the player|Hands:|Virtual headset connected)') { continue }
                if ($text -match '^Headset: the title delivered') {
                    $script:reports++
                    if (($script:reports % 6) -ne 1) { continue }
                }
                if ($text -match '^Controllers: standing in') {
                    if (($script:reports % 6) -ne 1) { continue }
                }
                if ($warning) { Say ("  " + $text) "Yellow" } else { Say ("  " + $text) }
            } elseif ($line -match '^\[Input\] <Info> \([^)]*\) \S+ (?:\w+: )?(Controller .*)$') {
                Say ("  " + $Matches[1])
            } elseif ($line -match '^\[Core\] <Info> \([^)]*\) \S+ (?:\w+: )?(The title draws at up to .*|The scene is drawn at .*|Frames are given .*)$') {
                Say ("  " + $Matches[1])
            } elseif ($line -match '<Critical>.*?: (.*)$') {
                $text = $Matches[1]
                if (-not $shown.ContainsKey($text)) { $shown[$text] = 1; Say ("  ! " + $text) "Red" }
            }
        }
        $script:position = $stream.Position
    } finally { $stream.Dispose() }
}
$reports = 0
while (-not $process.HasExited) {
    Start-Sleep -Milliseconds 700
    Show-Log
}
Show-Log
Say ""
if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) {
    Say ("The emulator ended with code " + $process.ExitCode + ". Its log is $log") "Yellow"
    Read-Host "Press Enter to close"
} else {
    Say "The game was closed."
    Start-Sleep -Seconds 2
}
