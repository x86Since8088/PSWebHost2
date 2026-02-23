# Bulk Fix Card Endpoints to JSON+scriptPath Pattern
# Converts HTML-returning cards and adds scriptPath to JSON-only cards

param(
    [switch]$WhatIf = $false
)

Write-Host "`n===== Bulk Card Endpoint Fix =====" -ForegroundColor Cyan
Write-Host "Mode: $(if ($WhatIf) { 'WHAT-IF (no changes)' } else { 'LIVE' })`n" -ForegroundColor $(if ($WhatIf) { 'Yellow' } else { 'Green' })

$fixed = 0
$skipped = 0
$errors = 0

# Read the list of cards needing fix
if (-not (Test-Path "cards_needing_fix.csv")) {
    Write-Host "Error: cards_needing_fix.csv not found. Run scan_card_patterns.ps1 first." -ForegroundColor Red
    exit 1
}

$needsFix = Import-Csv "cards_needing_fix.csv"

foreach ($card in $needsFix) {
    $filePath = $card.File
    Write-Host "`nProcessing: $filePath" -ForegroundColor Yellow

    if (-not (Test-Path $filePath)) {
        Write-Host "  × File not found" -ForegroundColor Red
        $errors++
        continue
    }

    $content = Get-Content $filePath -Raw

    # Determine component path and card name from file location
    $componentPath = $null
    $cardName = $null
    $appName = $null

    if ($filePath -match "routes[\\/]cards[\\/]([^\\/]+(?:[\\/][^\\/]+)?)[\\/]get\.ps1") {
        # Core card (may have subdirectory like admin/role-management)
        $cardName = $matches[1] -replace '\\', '/'
        $componentPath = "/public/elements/$cardName/component.js"
    }
    elseif ($filePath -match "apps[\\/]([^\\/]+)[\\/]routes[\\/]cards[\\/]([^\\/]+)[\\/]get\.ps1") {
        # App card
        $appName = $matches[1]
        $cardName = $matches[2]
        $componentPath = "/apps/$appName/public/elements/$cardName/component.js"
    }

    if (-not $componentPath) {
        Write-Host "  × Could not determine component path" -ForegroundColor Red
        $errors++
        continue
    }

    Write-Host "  Card: $cardName" -ForegroundColor Gray
    Write-Host "  Component: $componentPath" -ForegroundColor Gray

    # Apply fix based on pattern
    if ($card.Pattern -eq "HTML") {
        # Convert HTML-returning card to JSON pattern
        Write-Host "  Converting HTML → JSON+scriptPath..." -ForegroundColor Cyan

        # Determine card title from name
        $titleWords = ($cardName -replace '-', ' ').Split(' ') | ForEach-Object {
            $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower()
        }
        $cardTitle = $titleWords -join ' '

        # Create new JSON response code
        $newCode = @"
param (
    [System.Net.HttpListenerContext]`$Context,
    [System.Net.HttpListenerRequest]`$Request=`$Context.Request,
    [System.Net.HttpListenerResponse]`$Response=`$Context.Response,
    `$sessiondata
)

try {
    # Return card metadata (JSON pattern)
    `$cardInfo = @{
        component = '$($cardName -replace '/', '-')'
        scriptPath = '$componentPath'
        title = '$cardTitle'
        description = 'Card component'
    }

    context_response -Response `$Response -String (`$cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'CardLoad' -Message "Error loading card: `$(`$_.Exception.Message)"
    `$Report = Get-PSWebHostErrorReport -ErrorRecord `$_ -Context `$Context -Request `$Request -sessiondata `$sessiondata
    context_response -Response `$Response -StatusCode `$Report.statusCode -String `$Report.body -ContentType `$Report.contentType
}
"@

        if ($WhatIf) {
            Write-Host "  WHAT-IF: Would replace entire file with JSON pattern" -ForegroundColor Yellow
        } else {
            Set-Content -Path $filePath -Value $newCode -NoNewline
            Write-Host "  ✓ Converted to JSON+scriptPath pattern" -ForegroundColor Green
            $fixed++
        }
    }
    elseif ($card.Pattern -eq "JSON-only") {
        # Add scriptPath to existing JSON response
        Write-Host "  Adding scriptPath to existing JSON..." -ForegroundColor Cyan

        # Look for the hashtable definition and add scriptPath after the opening brace
        if ($content -match '(@\s*\{)\s*([\r\n]+\s*)') {
            $newContent = $content -replace '(@\s*\{)([\r\n]+\s*)', "`$1`$2        scriptPath = '$componentPath'`$2"

            if ($WhatIf) {
                Write-Host "  WHAT-IF: Would add scriptPath = '$componentPath'" -ForegroundColor Yellow
            } else {
                Set-Content -Path $filePath -Value $newContent -NoNewline
                Write-Host "  ✓ Added scriptPath field" -ForegroundColor Green
                $fixed++
            }
        } else {
            Write-Host "  × Failed to add scriptPath (pattern not matched)" -ForegroundColor Red
            Write-Host "    Consider manual fix for this file" -ForegroundColor Gray
            $errors++
        }
    }
    else {
        Write-Host "  - Skipped (unsupported pattern)" -ForegroundColor Gray
        $skipped++
    }
}

Write-Host "`n===== Fix Complete =====" -ForegroundColor Cyan
Write-Host "Fixed: $fixed" -ForegroundColor Green
Write-Host "Skipped: $skipped" -ForegroundColor Gray
Write-Host "Errors: $errors" -ForegroundColor $(if ($errors -gt 0) { 'Red' } else { 'Green' })

if (-not $WhatIf -and $fixed -gt 0) {
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "1. Restart the server" -ForegroundColor White
    Write-Host "2. Test cards in browser" -ForegroundColor White
    Write-Host "3. Check for any cards that need manual component path adjustment" -ForegroundColor White
}
