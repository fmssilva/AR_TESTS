param(
    [string]$FilteredPath = "_out.txt",
    [string]$RawPath = "_out.raw.txt"
)

$utf8 = New-Object System.Text.UTF8Encoding($false)

$patterns = @(
    '^(Launching|Running Gradle task|Built build|Installing build|Syncing files to device|Flutter run key commands\.|r Hot reload\.|R Hot restart\.|h List all available interactive commands\.|d Detach .*|c Clear the screen|q Quit .*|A Dart VM Service .*|The Flutter DevTools debugger .*|Lost connection to device\.)',
    '^[IWE]/flutter',
    '^[DWE]/ARController',
    '^[DWE]/ARProjection',
    '^[DWE]/WorldCoordManager',
    '^[DWE]/WorldCoordMath',
    '^[DWE]/POINodeBuilder',
    '^[DWE]/DiagnosticRenderer'
)

Remove-Item $FilteredPath -ErrorAction SilentlyContinue
Remove-Item $RawPath -ErrorAction SilentlyContinue

& flutter run 2>&1 | ForEach-Object {
    $line = [string]$_

    Write-Output $line
    [System.IO.File]::AppendAllText($RawPath, $line + [Environment]::NewLine, $utf8)

    foreach ($pattern in $patterns) {
        if ($line -match $pattern) {
            [System.IO.File]::AppendAllText($FilteredPath, $line + [Environment]::NewLine, $utf8)
            break
        }
    }
}