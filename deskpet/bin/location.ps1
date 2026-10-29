param(
    [Parameter(Mandatory = $true)][string]$Out
)

# One-shot Windows location lookup for DeskPet.
# Writes { ok, lat, lon, accuracy } or { ok:false, error } as UTF-8 JSON.
$ErrorActionPreference = "Stop"
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Devices.Geolocation.Geolocator, Windows, ContentType = WindowsRuntime]
    $locator = New-Object Windows.Devices.Geolocation.Geolocator
    $locator.DesiredAccuracyInMeters = 100
    $operation = $locator.GetGeopositionAsync()
    $task = $null
    try {
        $task = [System.WindowsRuntimeSystemExtensions]::AsTask($operation)
    } catch {
        $task = $null
    }
    if ($null -eq $task) {
        $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
            Where-Object {
                $_.Name -eq "AsTask" -and
                $_.IsGenericMethodDefinition -and
                $_.GetGenericArguments().Count -eq 1 -and
                $_.GetParameters().Count -eq 1
            } |
            Select-Object -First 1
        $generic = $method.MakeGenericMethod([Windows.Devices.Geolocation.Geoposition])
        $task = $generic.Invoke($null, @($operation))
    }
    if (-not $task.Wait(5000)) {
        throw "location timeout"
    }
    $coordinate = $task.Result.Coordinate
    $result = @{
        ok       = $true
        lat      = [double]$coordinate.Point.Position.Latitude
        lon      = [double]$coordinate.Point.Position.Longitude
        accuracy = [double]$coordinate.Accuracy
    }
} catch {
    $result = @{
        ok    = $false
        error = $_.Exception.Message
    }
}

$json = $result | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText($Out, $json, (New-Object System.Text.UTF8Encoding($false)))
