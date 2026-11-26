$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
Start-Process -FilePath $Godot -ArgumentList "--path", $Root, "--xr-mode", "off"

