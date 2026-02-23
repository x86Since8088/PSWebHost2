<#
.SYNOPSIS
    Automated test runner for all PSWebHost cards

.DESCRIPTION
    Discovers all cards via Get-DebugMenuCards and runs comprehensive tests on each.
    Supports filtering by tags and apps, parallel execution, and generates detailed reports.

.PARAMETER IncludeTags
    Array of tags to include (e.g., @("files", "monitoring"))

.PARAMETER ExcludeTags
    Array of tags to exclude (e.g., @("experimental", "deprecated"))

.PARAMETER AppsFilter
    Filter by app names (e.g., @("WebhostFileExplorer", "WebHostMetrics"))

.PARAMETER SessionID
    Target session ID. Defaults to "all".

.PARAMETER ReportPath
    Optional path to save HTML report

.PARAMETER Parallel
    Run tests in parallel (experimental)

.PARAMETER ThrottleLimit
    Maximum number of parallel tests (default: 3)

.PARAMETER TimeoutPerCard
    Timeout for each card test in seconds (default: 20)

.EXAMPLE
    Test-AllDebugCards

.EXAMPLE
    Test-AllDebugCards -ExcludeTags @("experimental") -ReportPath "C:\Reports\card-tests.html"

.EXAMPLE
    Test-AllDebugCards -IncludeTags @("files", "monitoring") -Parallel -ThrottleLimit 3

.OUTPUTS
    Returns comprehensive test run summary with results for all cards
#>
[CmdletBinding()]
param(
        [Parameter(Mandatory = $false)]
        [string[]]$IncludeTags,

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeTags,

        [Parameter(Mandatory = $false)]
        [string[]]$AppsFilter,

        [Parameter(Mandatory = $false)]
        [string]$SessionID = "all",

        [Parameter(Mandatory = $false)]
        [string]$ReportPath,

        [Parameter(Mandatory = $false)]
        [switch]$Parallel,

        [Parameter(Mandatory = $false)]
        [int]$ThrottleLimit = 3,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutPerCard = 20
    )

    $MyTag = '[Test-AllDebugCards]'

    $testRun = @{
        StartTime = Get-Date
        EndTime = $null
        Duration = 0
        TotalCards = 0
        Passed = 0
        Failed = 0
        Warnings = 0
        Results = @()
        Summary = @{
            ByApp = @{}
            FailedCards = @()
            WarnCards = @()
        }
    }

    try {
        Write-Host "`n$MyTag =====================================" -ForegroundColor Cyan
        Write-Host "$MyTag PSWebHost Comprehensive Card Testing" -ForegroundColor Cyan
        Write-Host "$MyTag =====================================" -ForegroundColor Cyan
        Write-Host ""

        # Step 1: Discover cards
        Write-Host "$MyTag Discovering cards..." -ForegroundColor Yellow

        $discoverParams = @{}
        if ($IncludeTags) { $discoverParams.Tags = $IncludeTags }
        if ($AppsFilter) { $discoverParams.AppFilter = $AppsFilter }

        $allCards = & "$PSScriptRoot\Get-DebugMenuCards.ps1" @discoverParams

        # Apply exclude tags filter
        if ($ExcludeTags) {
            $allCards = $allCards | Where-Object {
                $cardTags = $_.Tags
                $hasExcludedTag = $false
                foreach ($tag in $ExcludeTags) {
                    if ($cardTags -contains $tag) {
                        $hasExcludedTag = $true
                        break
                    }
                }
                return -not $hasExcludedTag
            }
        }

        $testRun.TotalCards = $allCards.Count

        Write-Host "$MyTag Found $($allCards.Count) cards to test" -ForegroundColor Green
        Write-Host ""

        if ($allCards.Count -eq 0) {
            Write-Warning "$MyTag No cards found to test"
            return $testRun
        }

        # Step 2: Run tests
        Write-Host "$MyTag Starting test execution..." -ForegroundColor Yellow
        Write-Host "$MyTag Parallel: $Parallel, Throttle: $ThrottleLimit, Timeout: ${TimeoutPerCard}s" -ForegroundColor Gray
        Write-Host ""

        if ($Parallel) {
            # Parallel execution (use ForEach-Object -Parallel in PS7+)
            Write-Host "$MyTag Running tests in parallel (throttle: $ThrottleLimit)..." -ForegroundColor Yellow

            $results = $allCards | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                $card = $_
                $sessionId = $using:SessionID
                $timeout = $using:TimeoutPerCard

                # Import functions in parallel context
                . $using:PSScriptRoot\Invoke-DebugCardTest.ps1
                . $using:PSScriptRoot\Test-DebugCardLoad.ps1
                . $using:PSScriptRoot\Launch-DebugCard.ps1
                . $using:PSScriptRoot\Close-DebugCard.ps1
                . $using:PSScriptRoot\Debug_Client_Command_Enqueue.ps1

                # Run test
                $result = Invoke-DebugCardTest -CardDefinition $card -SessionID $sessionId -TimeoutSeconds $timeout

                return $result
            }

            $testRun.Results = $results

        } else {
            # Sequential execution
            $cardNumber = 0
            foreach ($card in $allCards) {
                $cardNumber++

                Write-Host "$MyTag [$cardNumber/$($allCards.Count)] Testing: $($card.Name)" -ForegroundColor Cyan

                try {
                    $result = & "$PSScriptRoot\Invoke-DebugCardTest.ps1" `
                        -CardDefinition $card `
                        -SessionID $SessionID `
                        -TimeoutSeconds $TimeoutPerCard

                    $testRun.Results += $result

                    # Update counters
                    switch ($result.Status) {
                        "Pass" {
                            $testRun.Passed++
                            Write-Host "$MyTag   ✓ PASS" -ForegroundColor Green
                        }
                        "Warn" {
                            $testRun.Warnings++
                            Write-Host "$MyTag   ⚠ WARN" -ForegroundColor Yellow
                        }
                        "Fail" {
                            $testRun.Failed++
                            Write-Host "$MyTag   ✗ FAIL" -ForegroundColor Red
                        }
                    }

                } catch {
                    Write-Error "$MyTag Error testing card $($card.Name): $_"
                    $testRun.Failed++

                    $testRun.Results += @{
                        CardName = $card.Name
                        Url = $card.Url
                        Status = "Fail"
                        Errors = @("Exception: $($_.Exception.Message)")
                        Duration = 0
                    }
                }

                # Brief pause between cards
                Start-Sleep -Milliseconds 500
            }
        }

        # Step 3: Generate summary
        Write-Host ""
        Write-Host "$MyTag Generating summary..." -ForegroundColor Yellow

        # By-app summary
        foreach ($result in $testRun.Results) {
            $app = $result.AppName
            if (-not $testRun.Summary.ByApp.ContainsKey($app)) {
                $testRun.Summary.ByApp[$app] = @{
                    Passed = 0
                    Failed = 0
                    Warnings = 0
                    Total = 0
                }
            }

            $testRun.Summary.ByApp[$app].Total++

            switch ($result.Status) {
                "Pass" { $testRun.Summary.ByApp[$app].Passed++ }
                "Warn" { $testRun.Summary.ByApp[$app].Warnings++ }
                "Fail" { $testRun.Summary.ByApp[$app].Failed++ }
            }

            if ($result.Status -eq "Fail") {
                $testRun.Summary.FailedCards += $result.CardName
            } elseif ($result.Status -eq "Warn") {
                $testRun.Summary.WarnCards += $result.CardName
            }
        }

    } catch {
        Write-Error "$MyTag Critical error during test run: $_"

    } finally {
        # Finalize
        $testRun.EndTime = Get-Date
        $testRun.Duration = ($testRun.EndTime - $testRun.StartTime).TotalSeconds

        # Print summary
        Write-Host ""
        Write-Host "$MyTag =====================================" -ForegroundColor Cyan
        Write-Host "$MyTag Test Run Summary" -ForegroundColor Cyan
        Write-Host "$MyTag =====================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "$MyTag Total Cards Tested: $($testRun.TotalCards)" -ForegroundColor White
        Write-Host "$MyTag Passed:    $($testRun.Passed)" -ForegroundColor Green
        Write-Host "$MyTag Warnings:  $($testRun.Warnings)" -ForegroundColor Yellow
        Write-Host "$MyTag Failed:    $($testRun.Failed)" -ForegroundColor Red
        Write-Host "$MyTag Duration:  $([math]::Round($testRun.Duration, 2))s" -ForegroundColor Gray
        Write-Host ""

        # Failed cards
        if ($testRun.Summary.FailedCards.Count -gt 0) {
            Write-Host "$MyTag Failed Cards:" -ForegroundColor Red
            foreach ($card in $testRun.Summary.FailedCards) {
                Write-Host "$MyTag   - $card" -ForegroundColor Red
            }
            Write-Host ""
        }

        # Warning cards
        if ($testRun.Summary.WarnCards.Count -gt 0) {
            Write-Host "$MyTag Warning Cards:" -ForegroundColor Yellow
            foreach ($card in $testRun.Summary.WarnCards) {
                Write-Host "$MyTag   - $card" -ForegroundColor Yellow
            }
            Write-Host ""
        }

        # By-app summary
        if ($testRun.Summary.ByApp.Count -gt 0) {
            Write-Host "$MyTag Results by App:" -ForegroundColor Cyan
            foreach ($app in $testRun.Summary.ByApp.Keys | Sort-Object) {
                $appStats = $testRun.Summary.ByApp[$app]
                $passRate = if ($appStats.Total -gt 0) {
                    [math]::Round(($appStats.Passed / $appStats.Total) * 100, 1)
                } else { 0 }

                Write-Host "$MyTag   $app" -ForegroundColor White
                Write-Host "$MyTag     Pass: $($appStats.Passed)/$($appStats.Total) ($passRate%)" -ForegroundColor $(
                    if ($passRate -eq 100) { "Green" } elseif ($passRate -ge 50) { "Yellow" } else { "Red" }
                )
            }
            Write-Host ""
        }

        Write-Host "$MyTag =====================================" -ForegroundColor Cyan
        Write-Host ""

        # Save report if requested
        if ($ReportPath) {
            Write-Host "$MyTag Generating HTML report..." -ForegroundColor Yellow

            try {
                $htmlReport = & "$PSScriptRoot\New-DebugTestReport.ps1" -TestRun $testRun
                $htmlReport | Out-File -FilePath $ReportPath -Encoding UTF8 -Force

                Write-Host "$MyTag Report saved to: $ReportPath" -ForegroundColor Green
            } catch {
                Write-Error "$MyTag Failed to generate report: $_"
            }
        }
    }

return $testRun
