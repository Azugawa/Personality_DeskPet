param(
    [string]$GodotExe = $env:GODOT_EXE,
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path

if (-not $GodotExe) {
    $known = 'E:\Godot.exe\Godot_v4.7.2-stable_win64_console.exe'
    if (Test-Path -LiteralPath $known) {
        $GodotExe = $known
    } else {
        $command = Get-Command godot -ErrorAction SilentlyContinue
        if ($command) {
            $GodotExe = $command.Source
        } else {
            throw 'Set GODOT_EXE to a Godot 4 executable (console build preferred for test output).'
        }
    }
}
if (-not (Test-Path -LiteralPath $GodotExe)) {
    throw "Godot executable not found: $GodotExe"
}

Write-Output "Godot: $GodotExe"
Write-Output "Project: $ProjectPath"
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $GodotExe --headless --path $ProjectPath res://tests/test_runner.tscn 2>&1
$exitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorAction
Write-Output "Test exit code: $exitCode"
exit $exitCode
