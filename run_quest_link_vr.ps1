$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"

Write-Host "Starting VR Pruning in OpenXR VR mode via Meta Quest Link..."
Write-Host "Make sure Quest Link is active inside your Quest 3 headset first!"
Start-Process -FilePath $Godot -ArgumentList "--path", $Root
