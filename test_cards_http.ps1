#Requires -Version 7
# Card Validation via HTTP
# Tests all cards via HTTP endpoints

param(
    [int]$Port = 8080
)

$ErrorActionPreference = 'Continue'
$baseUrl = "http://localhost:$Port"

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "  Card Validation via HTTP" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Test server
Write-Host "[1/5] Testing Server..." -ForegroundColor Yellow

try {
    $response = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing -Method HEAD -TimeoutSec 30 -MaximumRedirection 5 -SessionVariable session
    Write-Host "  [OK] Server responding on port $Port" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Server not responding: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 2: Get main menu
Write-Host ""
Write-Host "[2/5] Fetching Main Menu..." -ForegroundColor Yellow

try {
    $menuResponse = Invoke-WebRequest -Uri "$baseUrl/api/v1/ui/elements/main-menu" -UseBasicParsing -TimeoutSec 30 -MaximumRedirection 5 -WebSession $session
    $menuData = $menuResponse.Content | ConvertFrom-Json
    Write-Host "  [OK] Main menu retrieved" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Could not fetch menu: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 3: Extract all card URLs
Write-Host ""
Write-Host "[3/5] Extracting Card URLs..." -ForegroundColor Yellow

function Find-CardUrls {
    param($items, $category = "")
    $urls = @()
    foreach ($item in $items) {
        $currentCat = if ($category) { "$category > $($item.label)" } else { $item.label }

        if ($item.url -and $item.url -match '/ui/elements/') {
            $urls += [PSCustomObject]@{
                Name = $item.label
                Url = $item.url
                Category = $category
                FullPath = $currentCat
            }
        }
        if ($item.children) {
            $urls += Find-CardUrls -items $item.children -category $currentCat
        }
    }
    return $urls
}

$allCards = Find-CardUrls -items $menuData
Write-Host "  [OK] Found $($allCards.Count) cards" -ForegroundColor Green

# Step 4: Test each card
Write-Host ""
Write-Host "[4/5] Testing Card Endpoints..." -ForegroundColor Yellow
Write-Host ""

$results = @()

foreach ($card in $allCards) {
    $cardName = $card.Name
    $cardUrl = $card.Url
    $fullUrl = "$baseUrl$cardUrl"

    Write-Host "Testing: $cardName" -ForegroundColor Cyan

    try {
        $response = Invoke-WebRequest -Uri $fullUrl -UseBasicParsing -TimeoutSec 30 -MaximumRedirection 5 -WebSession $session

        if ($response.StatusCode -eq 200) {
            # Try to parse as JSON
            try {
                $metadata = $response.Content | ConvertFrom-Json

                # Check for required fields
                $hasComponent = -not [string]::IsNullOrEmpty($metadata.component)
                $hasScriptPath = -not [string]::IsNullOrEmpty($metadata.scriptPath)
                $hasTitle = -not [string]::IsNullOrEmpty($metadata.title)

                if ($hasComponent -and $hasScriptPath) {
                    Write-Host "  [PASS] Valid JSON metadata" -ForegroundColor Green
                    Write-Host "    Component: $($metadata.component)" -ForegroundColor Gray
                    Write-Host "    Script: $($metadata.scriptPath)" -ForegroundColor Gray
                    if ($hasTitle) {
                        Write-Host "    Title: $($metadata.title)" -ForegroundColor Gray
                    }

                    $results += [PSCustomObject]@{
                        Card = $cardName
                        Category = $card.Category
                        Url = $cardUrl
                        Status = "PASS"
                        Format = "JSON"
                        Component = $metadata.component
                        ScriptPath = $metadata.scriptPath
                        HasTitle = $hasTitle
                        Width = $metadata.width
                        Height = $metadata.height
                    }
                } else {
                    Write-Host "  [WARN] JSON but missing required fields" -ForegroundColor Yellow
                    Write-Host "    Has component: $hasComponent" -ForegroundColor Gray
                    Write-Host "    Has scriptPath: $hasScriptPath" -ForegroundColor Gray

                    $results += [PSCustomObject]@{
                        Card = $cardName
                        Category = $card.Category
                        Url = $cardUrl
                        Status = "WARN"
                        Issue = "Missing required fields"
                        HasComponent = $hasComponent
                        HasScriptPath = $hasScriptPath
                    }
                }
            } catch {
                # Not JSON - might be legacy HTML
                $contentPreview = $response.Content.Substring(0, [Math]::Min(100, $response.Content.Length))
                $isHTML = $contentPreview -match '<html'

                if ($isHTML) {
                    Write-Host "  [WARN] Returns HTML instead of JSON (legacy)" -ForegroundColor Yellow
                    Write-Host "    Needs migration to JSON metadata format" -ForegroundColor Gray

                    $results += [PSCustomObject]@{
                        Card = $cardName
                        Category = $card.Category
                        Url = $cardUrl
                        Status = "LEGACY"
                        Format = "HTML"
                        Issue = "Needs migration to JSON"
                    }
                } else {
                    Write-Host "  [WARN] Unknown format" -ForegroundColor Yellow
                    Write-Host "    Preview: $contentPreview" -ForegroundColor Gray

                    $results += [PSCustomObject]@{
                        Card = $cardName
                        Category = $card.Category
                        Url = $cardUrl
                        Status = "WARN"
                        Issue = "Unknown format"
                    }
                }
            }
        } else {
            Write-Host "  [FAIL] HTTP $($response.StatusCode)" -ForegroundColor Red

            $results += [PSCustomObject]@{
                Card = $cardName
                Category = $card.Category
                Url = $cardUrl
                Status = "FAIL"
                Issue = "HTTP $($response.StatusCode)"
            }
        }
    } catch {
        Write-Host "  [FAIL] $($_.Exception.Message)" -ForegroundColor Red

        $results += [PSCustomObject]@{
            Card = $cardName
            Category = $card.Category
            Url = $cardUrl
            Status = "FAIL"
            Issue = $_.Exception.Message
        }
    }

    Write-Host ""
}

# Step 5: Summary
Write-Host ""
Write-Host "[5/5] Summary" -ForegroundColor Yellow
Write-Host ""

$passed = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$legacy = ($results | Where-Object { $_.Status -eq "LEGACY" }).Count
$warned = ($results | Where-Object { $_.Status -eq "WARN" }).Count
$failed = ($results | Where-Object { $_.Status -eq "FAIL" }).Count
$total = $results.Count

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "  Results" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Cards Tested: $total" -ForegroundColor White
Write-Host "  PASS (JSON):      $passed" -ForegroundColor Green
Write-Host "  LEGACY (HTML):    $legacy" -ForegroundColor Yellow
Write-Host "  WARN:             $warned" -ForegroundColor Yellow
Write-Host "  FAIL:             $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Gray" })
Write-Host ""

# Show by category
Write-Host "By Category:" -ForegroundColor Cyan
$results | Group-Object Category | Sort-Object Name | ForEach-Object {
    $cat = if ($_.Name) { $_.Name } else { "(Uncategorized)" }
    $catPass = ($_.Group | Where-Object { $_.Status -eq "PASS" }).Count
    $catTotal = $_.Count
    Write-Host "  $cat : $catPass/$catTotal passed" -ForegroundColor Gray
}

# Failed cards
if ($failed -gt 0) {
    Write-Host ""
    Write-Host "Failed Cards:" -ForegroundColor Red
    $results | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "  - $($_.Card): $($_.Issue)" -ForegroundColor Red
    }
}

# Legacy cards
if ($legacy -gt 0) {
    Write-Host ""
    Write-Host "Legacy Cards (Need Migration):" -ForegroundColor Yellow
    $results | Where-Object { $_.Status -eq "LEGACY" } | ForEach-Object {
        Write-Host "  - $($_.Card)" -ForegroundColor Yellow
    }
}

# Save report
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$reportPath = Join-Path $PSScriptRoot "card_validation_report_$timestamp.json"

$report = @{
    Timestamp = (Get-Date).ToString('o')
    ServerUrl = $baseUrl
    TotalCards = $total
    Results = @{
        Passed = $passed
        Legacy = $legacy
        Warned = $warned
        Failed = $failed
    }
    Cards = $results
}

$report | ConvertTo-Json -Depth 10 | Set-Content $reportPath -Encoding UTF8

Write-Host ""
Write-Host "Detailed report saved: $reportPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

# Export summary CSV
$csvPath = Join-Path $PSScriptRoot "card_validation_summary_$timestamp.csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "CSV export saved: $csvPath" -ForegroundColor Cyan

Write-Host ""

# Exit code
if ($failed -eq 0) {
    Write-Host "VALIDATION COMPLETE - All cards accessible!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "VALIDATION COMPLETE - Some failures detected" -ForegroundColor Yellow
    exit 1
}
