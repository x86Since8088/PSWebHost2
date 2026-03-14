# Scan Card Endpoints for Response Pattern

Write-Host "`n===== Scanning Card Endpoint Patterns =====" -ForegroundColor Cyan

$results = @()

# Find all card get.ps1 files
$cardFiles = @()
$cardFiles += Get-ChildItem -Path "routes/cards" -Filter "get.ps1" -Recurse -ErrorAction SilentlyContinue
$cardFiles += Get-ChildItem -Path "apps/*/routes/cards" -Filter "get.ps1" -Recurse -ErrorAction SilentlyContinue

Write-Host "Found $($cardFiles.Count) card endpoints to scan`n" -ForegroundColor Green

foreach ($file in $cardFiles) {
    $relativePath = $file.FullName.Replace((Get-Location).Path + "\", "")
    $content = Get-Content $file.FullName -Raw

    $pattern = "UNKNOWN"
    $hasScriptPath = $false
    $returnsHTML = $false
    $returnsJSON = $false

    # Check for scriptPath in response
    if ($content -match "scriptPath\s*=") {
        $hasScriptPath = $true
    }

    # Check if returns HTML
    if ($content -match "ContentType.*text/html" -or
        $content -match '@"\s*<(html|div|script)') {
        $returnsHTML = $true
        $pattern = "HTML"
    }

    # Check if returns JSON with ConvertTo-Json
    if ($content -match "ConvertTo-Json" -and
        $content -match "ContentType.*application/json") {
        $returnsJSON = $true
        if ($hasScriptPath) {
            $pattern = "JSON+scriptPath"
        } else {
            $pattern = "JSON-only"
        }
    }

    # Override if both
    if ($returnsHTML -and $returnsJSON) {
        if ($hasScriptPath) {
            $pattern = "MIXED+scriptPath"
        } else {
            $pattern = "MIXED"
        }
    }

    $results += [PSCustomObject]@{
        File = $relativePath
        Pattern = $pattern
        HasScriptPath = $hasScriptPath
        ReturnsHTML = $returnsHTML
        ReturnsJSON = $returnsJSON
    }
}

Write-Host "===== Results by Pattern =====" -ForegroundColor Cyan

$grouped = $results | Group-Object Pattern | Sort-Object Count -Descending

foreach ($group in $grouped) {
    $color = switch ($group.Name) {
        "JSON+scriptPath" { "Green" }
        "HTML" { "Red" }
        "JSON-only" { "Yellow" }
        default { "Gray" }
    }

    Write-Host "`n$($group.Name): $($group.Count) files" -ForegroundColor $color
    $group.Group | ForEach-Object {
        Write-Host "  - $($_.File)" -ForegroundColor Gray
    }
}

Write-Host "`n===== Summary =====" -ForegroundColor Cyan
Write-Host "Total cards: $($results.Count)" -ForegroundColor White
Write-Host "✓ JSON+scriptPath (good): $($results | Where-Object { $_.Pattern -eq 'JSON+scriptPath' } | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Green
Write-Host "⚠ JSON-only (missing scriptPath): $($results | Where-Object { $_.Pattern -eq 'JSON-only' } | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Yellow
Write-Host "× HTML (needs conversion): $($results | Where-Object { $_.Pattern -eq 'HTML' } | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Red

# Export for bulk fix
$needsFix = $results | Where-Object { $_.Pattern -in @('HTML', 'JSON-only', 'MIXED') }
if ($needsFix.Count -gt 0) {
    Write-Host "`n$($needsFix.Count) files need fixing" -ForegroundColor Yellow
    $needsFix | Select-Object File, Pattern | Export-Csv "cards_needing_fix.csv" -NoTypeInformation
    Write-Host "List exported to: cards_needing_fix.csv" -ForegroundColor Cyan
}
