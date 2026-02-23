#Requires -Version 7

<#
.SYNOPSIS
    Quick diagnostic test for Memory Explorer endpoint

.DESCRIPTION
    Tests that the Memory Explorer endpoint and streaming API are working correctly
#>

param(
    [string]$BaseUrl = "http://localhost:8080"
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Memory Explorer Endpoint Diagnostics" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Test 1: UI Endpoint
Write-Host "1. Testing UI endpoint..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BaseUrl/cards/memory-explorer" `
                                   -Method GET `
                                   -TimeoutSec 5 `
                                   -UseBasicParsing

    if ($response.StatusCode -eq 200) {
        Write-Host "   ✅ PASS: UI endpoint responds (200 OK)" -ForegroundColor Green

        if ($response.Content -match "memory-explorer") {
            Write-Host "   ✅ PASS: Response contains memory-explorer component" -ForegroundColor Green
        } else {
            Write-Host "   ❌ FAIL: Response missing memory-explorer component" -ForegroundColor Red
        }

        if ($response.Content -match "class MemoryExplorer extends HTMLElement") {
            Write-Host "   ✅ PASS: Web Component class found" -ForegroundColor Green
        } else {
            Write-Host "   ⚠️  WARN: Web Component class not found in response" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   ❌ FAIL: Unexpected status code: $($response.StatusCode)" -ForegroundColor Red
    }
} catch {
    Write-Host "   ❌ FAIL: Cannot reach UI endpoint" -ForegroundColor Red
    Write-Host "      Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "      Make sure PSWebHost is running on port 8080" -ForegroundColor Yellow
}

# Test 2: Memory Analysis Endpoint
Write-Host "`n2. Testing memory analysis endpoint (streaming)..." -ForegroundColor Yellow
try {
    # Create a test variable
    $Global:MemoryExplorerTest = @{
        Name = "TestData"
        Items = 1..50
        Nested = @{ SubItem = "Value" }
    }

    $url = "$BaseUrl/api/v1/debug/vars?format=memory&path=MemoryExplorerTest&depth=3&timeout=10"

    Write-Host "   URL: $url" -ForegroundColor Gray
    Write-Host "   Streaming NDJSON response..." -ForegroundColor Gray

    $webRequest = [System.Net.WebRequest]::Create($url)
    $webRequest.Method = "GET"
    $webRequest.Timeout = 15000

    $response = $webRequest.GetResponse()
    $stream = $response.GetResponseStream()
    $reader = [System.IO.StreamReader]::new($stream)

    $messageCount = 0
    $messageTypes = @()
    $foundVariable = $false

    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()

        if ($line.Trim()) {
            try {
                $message = $line | ConvertFrom-Json
                $messageCount++
                $messageTypes += $message.type

                Write-Host "      [$messageCount] $($message.type)" -ForegroundColor Cyan

                if ($message.type -eq 'variable' -and $message.name -eq 'MemoryExplorerTest') {
                    $foundVariable = $true
                    Write-Host "         Variable found: $($message.result.TotalSize) bytes" -ForegroundColor Green
                }

                # Stop after complete message
                if ($message.type -eq 'complete') {
                    Write-Host "      Analysis complete!" -ForegroundColor Green
                    break
                }
            } catch {
                Write-Host "      ⚠️  Failed to parse line: $line" -ForegroundColor Yellow
            }
        }

        # Safety: stop after 100 messages
        if ($messageCount -gt 100) {
            Write-Host "      Stopping after 100 messages" -ForegroundColor Yellow
            break
        }
    }

    $reader.Close()
    $stream.Close()
    $response.Close()

    Write-Host "`n   Summary:" -ForegroundColor White
    Write-Host "      Messages received: $messageCount" -ForegroundColor Cyan
    Write-Host "      Message types: $($messageTypes -join ', ')" -ForegroundColor Cyan

    if ($messageCount -gt 0) {
        Write-Host "   ✅ PASS: Streaming endpoint works" -ForegroundColor Green
    } else {
        Write-Host "   ❌ FAIL: No messages received" -ForegroundColor Red
    }

    if ($foundVariable) {
        Write-Host "   ✅ PASS: Test variable analyzed" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  WARN: Test variable not found in results" -ForegroundColor Yellow
    }

    # Cleanup
    Remove-Variable -Name MemoryExplorerTest -Scope Global -ErrorAction SilentlyContinue

} catch {
    Write-Host "   ❌ FAIL: Cannot reach streaming endpoint" -ForegroundColor Red
    Write-Host "      Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Module Verification
Write-Host "`n3. Verifying Memory Analysis module..." -ForegroundColor Yellow
try {
    $modulePath = "C:\SC\PsWebHost\modules\PSWebHost_MemoryAnalysis\PSWebHost_MemoryAnalysis.psd1"

    if (Test-Path $modulePath) {
        Write-Host "   ✅ PASS: Module files exist" -ForegroundColor Green

        Import-Module $modulePath -Force -ErrorAction Stop
        Write-Host "   ✅ PASS: Module imports successfully" -ForegroundColor Green

        $functions = @(
            'Get-MemoryConsumption',
            'Measure-ObjectGraph',
            'Get-TypeMemoryOverhead',
            'Get-AssemblyMemory'
        )

        $allFound = $true
        foreach ($func in $functions) {
            $cmd = Get-Command $func -ErrorAction SilentlyContinue
            if ($cmd) {
                Write-Host "      ✓ $func" -ForegroundColor Green
            } else {
                Write-Host "      ✗ $func NOT FOUND" -ForegroundColor Red
                $allFound = $false
            }
        }

        if ($allFound) {
            Write-Host "   ✅ PASS: All functions exported" -ForegroundColor Green
        } else {
            Write-Host "   ❌ FAIL: Some functions missing" -ForegroundColor Red
        }

    } else {
        Write-Host "   ❌ FAIL: Module files not found" -ForegroundColor Red
        Write-Host "      Expected: $modulePath" -ForegroundColor Gray
    }
} catch {
    Write-Host "   ❌ FAIL: Module verification failed" -ForegroundColor Red
    Write-Host "      Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Menu Entry
Write-Host "`n4. Checking menu integration..." -ForegroundColor Yellow
try {
    $menuPath = "C:\SC\PsWebHost\apps\WebHostDebugExtensions\menu.yaml"

    if (Test-Path $menuPath) {
        $menuContent = Get-Content $menuPath -Raw

        if ($menuContent -match "Memory Explorer") {
            Write-Host "   ✅ PASS: Menu entry exists" -ForegroundColor Green

            if ($menuContent -match "/cards/memory-explorer") {
                Write-Host "   ✅ PASS: URL correctly configured" -ForegroundColor Green
            } else {
                Write-Host "   ⚠️  WARN: URL may be incorrect" -ForegroundColor Yellow
            }
        } else {
            Write-Host "   ⚠️  WARN: Memory Explorer not found in menu" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   ⚠️  WARN: Menu file not found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ⚠️  WARN: Cannot verify menu" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Diagnostics Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Next Steps:" -ForegroundColor White
Write-Host "  1. Open browser: $BaseUrl/cards/memory-explorer" -ForegroundColor Cyan
Write-Host "  2. Click 'Analyze All Variables'" -ForegroundColor Cyan
Write-Host "  3. Watch real-time streaming analysis" -ForegroundColor Cyan
Write-Host "  4. Filter by size, search, export results" -ForegroundColor Cyan
Write-Host ""
