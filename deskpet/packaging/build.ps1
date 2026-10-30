param(
 [string]$Godot = 'E:\Godot.exe\Godot_v4.7.2-stable_win64_console.exe',
 [string]$Iscc = 'E:\DeskPet\build\tooling\InnoSetup\ISCC.exe',
 [string]$Version = '0.3.3'
)
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must be major.minor.patch' }
$repo = Split-Path (Split-Path $PSScriptRoot)
$project = Join-Path $repo 'deskpet'
New-Item -ItemType Directory -Force (Join-Path $repo 'build/windows') | Out-Null
$binDir = Join-Path $project 'bin'
New-Item -ItemType Directory -Force $binDir | Out-Null
& 'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe' /nologo /target:winexe "/out:$binDir\DeskPetSentinel.exe" /reference:System.Web.Extensions.dll /reference:System.Data.dll (Join-Path $PSScriptRoot 'SentinelHelper.cs') (Join-Path $PSScriptRoot 'DriveScan.cs') (Join-Path $PSScriptRoot 'Autostart.cs') 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Sentinel helper compilation failed' }
& $Godot --headless --path $project --editor --import --quit 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
& $Godot --headless --path $project --export-release 'Windows Desktop' (Join-Path $repo 'build/windows/DeskPet.exe') 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Godot export failed' }
& 'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe' /nologo /target:winexe /reference:System.Windows.Forms.dll /out:build/windows/DeskPetUpdater.exe (Join-Path $PSScriptRoot 'UpdateHelper.cs') 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Updater compilation failed' }
& $Iscc "/DAppVersion=$Version" (Join-Path $PSScriptRoot 'deskpet.iss') 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
$installer = Join-Path $repo "build/installer/DeskPet-Setup-$Version.exe"
$manifest = @{
 version = $Version
 url = "https://github.com/Azugawa/Personality_DeskPet/releases/download/v$Version/DeskPet-Setup-$Version.exe"
 sha256 = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifest | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $repo 'build/installer/update.json')
Write-Output $installer

& (Join-Path $PSScriptRoot "build_chunks.ps1") -Version $Version
