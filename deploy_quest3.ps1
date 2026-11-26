param(
    [switch]$Rebuild
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ApkPath = Join-Path $Root "builds\VRPruning-Quest3.apk"
$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$Godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"

if ($Rebuild -or -not (Test-Path $ApkPath)) {
    Write-Host "Building Meta Quest 3 APK..."
    & $Godot --headless --path $Root --export-debug "Meta Quest" "builds/VRPruning-Quest3.apk"
    if ($LASTEXITCODE -ne 0) { throw "Godot APK export failed with exit code $LASTEXITCODE" }
}

Write-Host "Starting ADB server..."
& $Adb start-server | Out-Null
Start-Sleep -Seconds 2

Write-Host "Checking connected Meta Quest 3 via ADB..."
$devices = & $Adb devices
Write-Host $devices
if (-not ($devices -match "\tdevice$")) {
    Write-Warning "No authorized Quest 3 detected via USB-C. Enable Developer Mode in Meta Horizon app, connect USB-C, and accept 'Allow USB debugging' inside the headset."
    exit 1
}

Write-Host "Installing $ApkPath onto Quest 3..."
& $Adb install -r $ApkPath
if ($LASTEXITCODE -ne 0) { throw "adb install failed" }

Write-Host "Launching VR Pruning on Quest 3..."
& $Adb shell am start -W -n "com.arbormr.quest3treepruning/com.godot.game.GodotAppLauncher"

