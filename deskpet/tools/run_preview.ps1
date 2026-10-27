param(
    [switch]$DesktopMode,
    [switch]$Editor,
    [string]$GodotExe = $env:GODOT_EXE,
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path

if (-not $GodotExe) {
    $known = 'E:\Godot.exe\Godot_v4.7.2-stable_win64.exe'
    if (Test-Path -LiteralPath $known) {
        $GodotExe = $known
    } else {
        $command = Get-Command godot -ErrorAction SilentlyContinue
        if ($command) {
            $GodotExe = $command.Source
        } else {
            throw 'Set GODOT_EXE to a Godot 4 GUI executable.'
        }
    }
}
if (-not (Test-Path -LiteralPath $GodotExe)) {
    throw "Godot executable not found: $GodotExe"
}

$arguments = @('--path', $ProjectPath)
if ($Editor) {
    $arguments += '--editor'
}
if ($DesktopMode) {
    $arguments += @('--', '--desktop-mode')
}

Write-Output "Godot: $GodotExe"
Write-Output "Arguments: $($arguments -join ' ')"
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $GodotExe @arguments
$exitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorAction
exit $exitCode
