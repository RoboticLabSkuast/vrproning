param(
    [switch]$Rebuild,
    [switch]$VR,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$WinDir = Join-Path $Root "builds\windows"
$ExePath = Join-Path $WinDir "VRPruning.exe"
$Godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"

if ($Rebuild -or -not (Test-Path $ExePath)) {
    New-Item -ItemType Directory -Force -Path $WinDir | Out-Null
    Write-Host "Building Windows Desktop executable..."
    & $Godot --headless --path $Root --xr-mode off --export-release "Windows Desktop" "builds/windows/VRPruning.exe"
    if ($LASTEXITCODE -ne 0) { throw "Godot Windows export failed with exit code $LASTEXITCODE" }
}

if (Test-Path $WinDir) {
    Set-Content -Path (Join-Path $WinDir "Play_VRPruning_Desktop.bat") -Value "@echo off`r`nstart `"`" `"%~dp0VRPruning.exe`" --xr-mode off`r`n" -Encoding ASCII
    Set-Content -Path (Join-Path $WinDir "Play_VRPruning_QuestLink_VR.bat") -Value "@echo off`r`nstart `"`" `"%~dp0VRPruning.exe`"`r`n" -Encoding ASCII
}

Write-Host "Windows build ready: $ExePath"
if (-not $NoLaunch) {
    $argsList = if ($VR) { @() } else { @("--xr-mode", "off") }
    Write-Host ("Launching VRPruning.exe " + ($argsList -join " "))
    if ($argsList.Count -gt 0) {
        Start-Process -FilePath $ExePath -ArgumentList $argsList
    } else {
        Start-Process -FilePath $ExePath
    }
}
