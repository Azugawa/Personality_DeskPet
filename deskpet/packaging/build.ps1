param(
 [string]$Godot = 'E:\Godot.exe\Godot_v4.7.2-stable_win64_console.exe',
 [string]$Iscc = 'E:\DeskPet\build\tooling\InnoSetup\ISCC.exe',
 [string]$Version = '0.2.9'
)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must be major.minor.patch' }
$repo = Split-Path (Split-Path $PSScriptRoot)
$project = Join-Path $repo 'deskpet'
New-Item -ItemType Directory -Force (Join-Path $repo 'build/windows') | Out-Null
& $Godot --headless --path $project --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
& $Godot --headless --path $project --export-release 'Windows Desktop' (Join-Path $repo 'build/windows/DeskPet.exe')
if ($LASTEXITCODE -ne 0) { throw 'Godot export failed' }
& 'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe' /nologo /target:winexe /reference:System.Windows.Forms.dll /out:build/windows/DeskPetUpdater.exe (Join-Path $PSScriptRoot 'UpdateHelper.cs')
if ($LASTEXITCODE -ne 0) { throw 'Updater compilation failed' }
& $Iscc "/DAppVersion=$Version" (Join-Path $PSScriptRoot 'deskpet.iss')
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
