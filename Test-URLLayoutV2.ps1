#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests the v2 URL layout system for proper card dimension restoration
.DESCRIPTION
    This script tests:
    1. URL encoding with v2 format
    2. Endpoint URL storage
    3. Card dimension restoration on page load
    4. Two-step rendering pattern
#>

param(
    [string]$BaseUrl = "http://localhost:8080"
)

Write-Host "`n=== Testing v2 URL Layout System ===" -ForegroundColor Cyan

# Test 1: Verify server is running
Write-Host "`n[Test 1] Checking server status..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BaseUrl/spa" -UseBasicParsing -TimeoutSec 5
    if ($response.StatusCode -eq 200) {
        Write-Host "✓ Server is running at $BaseUrl" -ForegroundColor Green
    }
} catch {
    Write-Host "✗ Server is not accessible at $BaseUrl" -ForegroundColor Red
    Write-Host "  Please start the server with .\WebHost.ps1" -ForegroundColor Yellow
    exit 1
}

# Test 2: Check if endpoint returns scriptPath
Write-Host "`n[Test 2] Verifying endpoint metadata format..." -ForegroundColor Yellow
$endpointTests = @(
    "/apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer",
    "/apps/WebhostRealtimeEvents/api/v1/ui/elements/realtime-events"
)

foreach ($endpoint in $endpointTests) {
    try {
        $response = Invoke-RestMethod -Uri "$BaseUrl$endpoint" -Method Get

        if ($response.scriptPath) {
            Write-Host "✓ $endpoint" -ForegroundColor Green
            Write-Host "  scriptPath: $($response.scriptPath)" -ForegroundColor Gray
        } elseif ($response.componentPath) {
            Write-Host "⚠ $endpoint uses componentPath (should be scriptPath)" -ForegroundColor Yellow
            Write-Host "  componentPath: $($response.componentPath)" -ForegroundColor Gray
        } else {
            Write-Host "✗ $endpoint missing scriptPath/componentPath" -ForegroundColor Red
        }
    } catch {
        Write-Host "✗ Failed to fetch: $endpoint" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
    }
}

# Test 3: Verify v2 URL format structure
Write-Host "`n[Test 3] Testing v2 URL format encoding/decoding..." -ForegroundColor Yellow

# Create a sample v2 layout
$v2Layout = @{
    version = 2
    cards = @(
        @{
            id = "realtime-events-test123"
            x = 0
            y = 0
            w = 12
            h = 30
            elementId = "realtime-events"
            title = "Real-time Events"
            endpoint = "/apps/WebhostRealtimeEvents/api/v1/ui/elements/realtime-events"
        }
    )
} | ConvertTo-Json -Compress

Write-Host "  Sample v2 layout:" -ForegroundColor Gray
Write-Host "  $v2Layout" -ForegroundColor DarkGray

# Encode it like the SPA does
$bytes = [System.Text.Encoding]::UTF8.GetBytes($v2Layout)
$base64 = [Convert]::ToBase64String($bytes)
$urlEncoded = [Uri]::EscapeDataString($base64)

Write-Host "`n  Encoded URL parameter:" -ForegroundColor Gray
Write-Host "  $urlEncoded" -ForegroundColor DarkGray
Write-Host "`n  Full test URL:" -ForegroundColor Gray
Write-Host "  $BaseUrl/spa?layout=$urlEncoded" -ForegroundColor DarkGray

# Decode it back to verify
$decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([Uri]::UnescapeDataString($urlEncoded)))
$parsedLayout = $decoded | ConvertFrom-Json

if ($parsedLayout.version -eq 2 -and $parsedLayout.cards.Count -eq 1) {
    Write-Host "`n✓ v2 format encoding/decoding works correctly" -ForegroundColor Green
    Write-Host "  Version: $($parsedLayout.version)" -ForegroundColor Gray
    Write-Host "  Cards: $($parsedLayout.cards.Count)" -ForegroundColor Gray
    Write-Host "  First card endpoint: $($parsedLayout.cards[0].endpoint)" -ForegroundColor Gray
    Write-Host "  First card dimensions: w=$($parsedLayout.cards[0].w) h=$($parsedLayout.cards[0].h)" -ForegroundColor Gray
} else {
    Write-Host "✗ v2 format encoding/decoding failed" -ForegroundColor Red
}

# Test 4: Manual browser test instructions
Write-Host "`n[Test 4] Manual Browser Testing Required" -ForegroundColor Yellow
Write-Host @"

To test card dimension restoration:

1. Open browser to: $BaseUrl/spa

2. Open a card (e.g., Real-time Events from main menu)

3. Resize the card to specific dimensions (e.g., w=12, h=30)

4. Check the URL - should see ?layout=<base64>

5. Copy the full URL

6. Open a new browser tab

7. Paste the URL and press Enter

8. Open browser DevTools Console (F12)

9. Verify console shows:
   [URL Layout] Loaded v2 layout from URL: {cardCount: 1}
   [URL Layout] Setting temporary grid layout for rendering
   [URL Layout] Applying actual card dimensions from URL
   [URL Layout] ✓ Self-contained layout loaded successfully

10. Verify the card appears at the EXACT dimensions you set

11. Verify NO "NaN for value attribute" warnings appear

Expected Result:
✓ Card loads at exact position and size
✓ No errors about "No componentPath specified"
✓ No NaN warnings
✓ Network tab shows:
  - GET to endpoint (e.g., /apps/WebhostRealtimeEvents/api/v1/ui/elements/realtime-events)
  - GET to scriptPath (e.g., /apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js)
  - NO GET to /public/layout.json

"@ -ForegroundColor White

Write-Host "`n=== Quick Test URL ===" -ForegroundColor Cyan
Write-Host "`nYou can test with this pre-made URL:" -ForegroundColor Yellow
Write-Host "$BaseUrl/spa?layout=$urlEncoded" -ForegroundColor White

Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Automated checks completed. Manual browser testing required for full validation." -ForegroundColor White
Write-Host ""
