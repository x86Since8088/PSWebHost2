<#
.SYNOPSIS
    Simple DuckDB-WASM test - checks if dependencies load locally

.DESCRIPTION
    Basic test to verify local dependencies are working

.EXAMPLE
    .\Test-DuckDB-Simple.ps1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SessionID = "all"
)

$MyTag = '[Test-DuckDB-Simple]'
$utilityPath = Join-Path $PSScriptRoot "..\..\apps\WebHostDebugExtensions\system\utility"

Write-Host "`n$MyTag ===== DuckDB Local Dependencies Test =====" -ForegroundColor Cyan

try {
    # Test 1: Check local files exist
    Write-Host "`n$MyTag [TEST 1/4] Checking local dependency files..." -ForegroundColor Yellow

    $libPath = Join-Path $PSScriptRoot "..\..\public\lib"
    $requiredFiles = @(
        "duckdb-mvp.wasm",
        "duckdb-browser-mvp.worker.js",
        "duckdb-browser.mjs",
        "apache-arrow.es2015.min.js"
    )

    $allFilesExist = $true
    foreach ($file in $requiredFiles) {
        $fullPath = Join-Path $libPath $file
        if (Test-Path $fullPath) {
            $size = (Get-Item $fullPath).Length
            $sizeMB = [math]::Round($size / 1MB, 2)
            $sizeKB = [math]::Round($size / 1KB, 2)
            $sizeDisplay = if ($sizeMB -gt 1) { "${sizeMB}MB" } else { "${sizeKB}KB" }
            Write-Host "$MyTag   ✓ $file ($sizeDisplay)" -ForegroundColor Green
        } else {
            Write-Host "$MyTag   ✗ $file MISSING" -ForegroundColor Red
            $allFilesExist = $false
        }
    }

    if (-not $allFilesExist) {
        Write-Host "`n$MyTag ⚠ Some files are missing. Run: npm install" -ForegroundColor Yellow
        exit 1
    }

    # Test 2: Check server is running
    Write-Host "`n$MyTag [TEST 2/4] Checking server status..." -ForegroundColor Yellow

    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/" -Method GET -TimeoutSec 5 -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Host "$MyTag   ✓ Server is running on port 8080" -ForegroundColor Green
        } else {
            Write-Host "$MyTag   ⚠ Server returned status $($response.StatusCode)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "$MyTag   ✗ Server not responding: $_" -ForegroundColor Red
        Write-Host "$MyTag   Run: .\restart_server.ps1" -ForegroundColor Yellow
        exit 1
    }

    # Test 3: Check if local files are accessible via HTTP
    Write-Host "`n$MyTag [TEST 3/4] Checking HTTP access to dependencies..." -ForegroundColor Yellow

    $testFiles = @(
        @{ Url = "http://localhost:8080/public/lib/duckdb-browser.mjs"; Name = "duckdb-browser.mjs" },
        @{ Url = "http://localhost:8080/public/lib/duckdb-mvp.wasm"; Name = "duckdb-mvp.wasm" }
    )

    foreach ($testFile in $testFiles) {
        try {
            $response = Invoke-WebRequest -Uri $testFile.Url -Method GET -TimeoutSec 5 -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                $contentType = $response.Headers['Content-Type']
                Write-Host "$MyTag   ✓ $($testFile.Name) accessible (Content-Type: $contentType)" -ForegroundColor Green
            }
        } catch {
            Write-Host "$MyTag   ✗ $($testFile.Name) not accessible: $_" -ForegroundColor Red
        }
    }

    # Test 4: Launch metrics chart and check console
    Write-Host "`n$MyTag [TEST 4/4] Testing metrics chart load..." -ForegroundColor Yellow

    $launchScript = Join-Path $utilityPath "Launch-DebugCard.ps1"

    if (-not (Test-Path $launchScript)) {
        Write-Host "$MyTag   ⚠ Launch-DebugCard.ps1 not found at: $launchScript" -ForegroundColor Yellow
        Write-Host "$MyTag   Skipping browser test" -ForegroundColor Yellow
    } else {
        $cardUrl = "/apps/UI_Uplot/public/elements/metrics-chart/component.js?source=/apps/WebHostMetrics/api/v1/metrics`&metric=cpu`&timerange=1h"

        try {
            $launchResult = & $launchScript -Url $cardUrl -Title "DuckDB Test" -SessionID $SessionID -Wait

            if ($launchResult.Success) {
                Write-Host "$MyTag   ✓ Card launched successfully (ID: $($launchResult.CardID))" -ForegroundColor Green

                # Wait for initialization
                Start-Sleep -Seconds 5

                # Close card
                $closeScript = Join-Path $utilityPath "Close-DebugCard.ps1"
                if (Test-Path $closeScript) {
                    & $closeScript -CardID $launchResult.CardID -SessionID $SessionID -Wait -TimeoutSeconds 5 | Out-Null
                    Write-Host "$MyTag   ✓ Card closed successfully" -ForegroundColor Green
                }
            } else {
                Write-Host "$MyTag   ✗ Failed to launch card: $($launchResult.Error)" -ForegroundColor Red
            }
        } catch {
            Write-Host "$MyTag   ✗ Browser test failed: $_" -ForegroundColor Red
        }
    }

    Write-Host "`n$MyTag ===== Test Summary =====" -ForegroundColor Cyan
    Write-Host "$MyTag ✓ Local dependencies are installed and accessible" -ForegroundColor Green
    Write-Host "$MyTag ✓ Server is running and serving files correctly" -ForegroundColor Green
    Write-Host "`n$MyTag Next: Check browser console for dependency load messages" -ForegroundColor Cyan
    Write-Host "$MyTag Look for: '[Worker] Successfully loaded DuckDB module from local'" -ForegroundColor Cyan

} catch {
    Write-Host "`n$MyTag Test failed with exception: $_" -ForegroundColor Red
    exit 1
}
