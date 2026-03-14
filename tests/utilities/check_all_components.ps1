# Check all card components and generate CSV reference
Write-Host "=== Card Component Audit ===" -ForegroundColor Cyan

$results = @()
$componentIssues = @()

# Find all card endpoints
$cardEndpoints = Get-ChildItem -Recurse -Filter "get.ps1" | Where-Object { $_.FullName -match "[\\/]cards[\\/]" }

Write-Host "`nFound $($cardEndpoints.Count) card endpoints" -ForegroundColor Yellow
Write-Host "Checking components..." -ForegroundColor Yellow

foreach ($endpoint in $cardEndpoints) {
    # Read endpoint file to find component reference
    $content = Get-Content $endpoint.FullName -Raw

    # Extract card name from path
    $relativePath = $endpoint.FullName -replace [regex]::Escape($PSScriptRoot), ''
    $relativePath = $relativePath -replace '^[\\/]', ''

    # Determine card name and component path
    $cardName = $null
    $componentPath = $null
    $elementId = $null
    $hasIframe = $false
    $hasComponent = $false
    $componentExists = $false
    $cardType = "Unknown"
    $issues = @()

    # Check if it's a core card or app card
    if ($relativePath -match '^routes[\\/]cards[\\/]([^\\/]+)') {
        $cardName = $matches[1]
        $elementId = $cardName
        $componentPath = "public\elements\$cardName\component.js"
        $cardType = "Core"
    } elseif ($relativePath -match '^apps[\\/]([^\\/]+)[\\/]routes[\\/]cards[\\/]([^\\/]+)') {
        $appName = $matches[1]
        $cardName = $matches[2]
        $elementId = $cardName
        $componentPath = "apps\$appName\public\elements\$cardName\component.js"
        $cardType = "App"
    }

    # Check content for component or iframe references
    if ($content -match 'componentScript\s*=|componentPath\s*=|component\.js') {
        $hasComponent = $true
    }
    if ($content -match 'iframe|IFrame') {
        $hasIframe = $true
    }

    # Check if component file exists
    if ($componentPath) {
        $fullComponentPath = Join-Path $PSScriptRoot $componentPath
        if (Test-Path $fullComponentPath) {
            $componentExists = $true

            # Read component to check for issues
            $compContent = Get-Content $fullComponentPath -Raw

            # Check for text/background contrast issues
            if ($compContent -match 'color:\s*[''"]?(#(?:000|333|555)|black|darkgray)' -and
                $compContent -notmatch 'background.*white|background.*#f|background.*#e') {
                $issues += "Dark text without light background"
            }

            # Check for title card usage
            if ($cardName -eq 'main-menu' -and $compContent -notmatch 'card-title|CardTitle') {
                $issues += "Missing title card implementation"
            }

        } else {
            $issues += "Component file missing"
        }
    }

    # Determine status
    $status = if ($componentExists) { "OK" }
              elseif ($hasIframe) { "Iframe" }
              elseif ($hasComponent) { "Missing" }
              else { "Unknown" }

    $results += [PSCustomObject]@{
        CardName = $cardName
        ElementId = $elementId
        Type = $cardType
        EndpointPath = $relativePath
        ComponentPath = $componentPath
        Status = $status
        HasComponent = $hasComponent
        HasIframe = $hasIframe
        ComponentExists = $componentExists
        Issues = ($issues -join "; ")
    }

    if ($issues.Count -gt 0) {
        $componentIssues += [PSCustomObject]@{
            Card = $cardName
            Issues = ($issues -join "; ")
            Path = $componentPath
        }
    }
}

# Display summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$okCount = ($results | Where-Object { $_.Status -eq "OK" }).Count
$missingCount = ($results | Where-Object { $_.Status -eq "Missing" }).Count
$iframeCount = ($results | Where-Object { $_.Status -eq "Iframe" }).Count
$unknownCount = ($results | Where-Object { $_.Status -eq "Unknown" }).Count

Write-Host "  OK (Component exists): $okCount" -ForegroundColor Green
Write-Host "  Missing Component: $missingCount" -ForegroundColor Red
Write-Host "  Iframe Cards: $iframeCount" -ForegroundColor Yellow
Write-Host "  Unknown: $unknownCount" -ForegroundColor Gray

# Show components with issues
if ($componentIssues.Count -gt 0) {
    Write-Host "`n=== Components with Issues ===" -ForegroundColor Yellow
    $componentIssues | Format-Table -AutoSize | Out-String | Write-Host
}

# Export results to CSV
$csvPath = Join-Path $PSScriptRoot "COMPONENT_AUDIT_RESULTS.csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "`nResults exported to: $csvPath" -ForegroundColor Green

# Return results for further processing
return $results
