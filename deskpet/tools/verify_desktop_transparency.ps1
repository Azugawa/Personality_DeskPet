param(
    [string]$GodotExe = $env:GODOT_EXE,
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'docs\screenshots\desktop_os_capture.png'),
    [int]$WaitSeconds = 15
)

$ErrorActionPreference = 'Stop'

if (-not $GodotExe) {
    $known = 'E:\Godot.exe\Godot_v4.7.2-stable_win64.exe'
    if (Test-Path -LiteralPath $known) {
        $GodotExe = $known
    } else {
        $command = Get-Command godot -ErrorAction SilentlyContinue
        if ($command) {
            $GodotExe = $command.Source
        } else {
            throw 'Set GODOT_EXE to a Godot 4 executable (GUI build, not the console build).'
        }
    }
}
if (-not (Test-Path -LiteralPath $GodotExe)) {
    throw "Godot executable not found: $GodotExe"
}
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDir = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class DeskPetWin32 {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
"@
# Make capture coordinates physical pixels, matching the 125% display scale.
[DeskPetWin32]::SetProcessDPIAware() | Out-Null

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
$form.BackColor = [System.Drawing.Color]::Magenta
$form.ShowInTaskbar = $false
$form.TopMost = $true
$godot = $null

try {
    $form.Show()
    $form.Activate()
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 400
    [System.Windows.Forms.Application]::DoEvents()

    $arguments = @('--path', ('"' + $ProjectPath + '"'), '--', '--desktop-mode')
    $godot = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WorkingDirectory $ProjectPath -PassThru

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $handle = [IntPtr]::Zero
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
        [System.Windows.Forms.Application]::DoEvents()
        if ($godot.HasExited) {
            throw "Godot exited before its window appeared (exit code $($godot.ExitCode))."
        }
        $godot.Refresh()
        if ($godot.MainWindowHandle -ne [IntPtr]::Zero) {
            $handle = $godot.MainWindowHandle
            break
        }
    }
    if ($handle -eq [IntPtr]::Zero) {
        throw "Godot window did not appear within $WaitSeconds seconds."
    }

    # Both windows are topmost: put the pet above the magenta form explicitly.
    # SWP_NOSIZE(0x1) | SWP_NOMOVE(0x2) | SWP_SHOWWINDOW(0x40)
    [DeskPetWin32]::SetWindowPos($handle, [IntPtr](-1), 0, 0, 0, 0, 0x43) | Out-Null
    Start-Sleep -Seconds 2
    [System.Windows.Forms.Application]::DoEvents()

    $rect = New-Object DeskPetWin32+RECT
    if (-not [DeskPetWin32]::GetWindowRect($handle, [ref]$rect)) {
        throw 'GetWindowRect failed for the Godot window.'
    }
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -le 0 -or $height -le 0) {
        throw "Invalid Godot window rect: $($rect.Left),$($rect.Top) $($width)x$($height)"
    }

    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size($width, $height)))
        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
    }

    $corners = @(
        $bitmap.GetPixel(2, 2),
        $bitmap.GetPixel($width - 3, 2),
        $bitmap.GetPixel(2, $height - 3),
        $bitmap.GetPixel($width - 3, $height - 3)
    )
    $magentaPixels = 0
    $sampledPixels = 0
    for ($y = 0; $y -lt $height; $y += 16) {
        for ($x = 0; $x -lt $width; $x += 16) {
            $color = $bitmap.GetPixel($x, $y)
            $sampledPixels++
            if ($color.R -gt 200 -and $color.G -lt 80 -and $color.B -gt 200) {
                $magentaPixels++
            }
        }
    }
    $ratio = if ($sampledPixels -gt 0) { [math]::Round($magentaPixels / $sampledPixels, 4) } else { 0 }

    Write-Output "SCREEN_BOUNDS=$([System.Windows.Forms.Screen]::PrimaryScreen.Bounds)"
    Write-Output "WINDOW_RECT=$($rect.Left),$($rect.Top),$width,$height"
    Write-Output "OUTPUT=$OutputPath"
    Write-Output ("CORNERS=" + (($corners | ForEach-Object { "($($_.R),$($_.G),$($_.B))" }) -join ' '))
    Write-Output "MAGENTA_SAMPLES=$magentaPixels/$sampledPixels RATIO=$ratio"

    if ($ratio -lt 0.35) {
        Write-Output 'RESULT=FAIL (transparent backdrop was not visible through the window)'
        exit 2
    }
    if ($ratio -gt 0.95) {
        Write-Output 'RESULT=FAIL (the backdrop covered the pet window; capture order is wrong)'
        exit 3
    }
    Write-Output 'RESULT=PASS (magenta desktop backdrop is visible through transparent window areas)'
}
finally {
    if ($godot -ne $null) {
        $godot.Refresh()
        if (-not $godot.HasExited) {
            Stop-Process -Id $godot.Id -Force -ErrorAction SilentlyContinue
        }
    }
    $form.Close()
    $form.Dispose()
}
