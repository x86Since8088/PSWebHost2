<#
.SYNOPSIS
    Runs comprehensive test suite on a single card

.DESCRIPTION
    Performs full testing of a card including:
    - Load success/failure
    - Component registration verification
    - DOM structure validation
    - Interactive element detection
    - Type-specific tests based on card category
    - Performance metrics

.PARAMETER CardDefinition
    Card definition object from Get-DebugMenuCards

.PARAMETER Url
    Direct URL to test (alternative to CardDefinition)

.PARAMETER Title
    Card title (used with -Url)

.PARAMETER SessionID
    Target session ID. Defaults to "all".

.PARAMETER TimeoutSeconds
    Maximum time for test operations (default: 20 seconds)

.EXAMPLE
    $cards = Get-DebugMenuCards
    Invoke-DebugCardTest -CardDefinition $cards[0]

.EXAMPLE
    Invoke-DebugCardTest -Url "/apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer" -Title "File Explorer"

.OUTPUTS
    Returns comprehensive test result with Pass/Fail/Warn status
#>
[CmdletBinding(DefaultParameterSetName = 'Definition')]
param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Definition')]
        [PSCustomObject]$CardDefinition,

        [Parameter(Mandatory = $true, ParameterSetName = 'Direct')]
        [string]$Url,

        [Parameter(Mandatory = $false, ParameterSetName = 'Direct')]
        [string]$Title = "Test Card",

        [Parameter(Mandatory = $false)]
        [string]$SessionID = "all",

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 20
    )

    $MyTag = '[Invoke-DebugCardTest]'

    # Determine card info from parameter set
    if ($PSCmdlet.ParameterSetName -eq 'Definition') {
        $Url = $CardDefinition.Url
        $Title = $CardDefinition.Name
        $elementId = $CardDefinition.ElementID
        $tags = $CardDefinition.Tags
        $appName = $CardDefinition.AppName
    } else {
        # Extract element ID from URL
        $elementId = if ($Url -match '/ui/elements/([^/\?]+)') { $matches[1] } else { 'unknown' }
        $tags = @()
        $appName = 'unknown'
    }

    $testResult = @{
        CardName = $Title
        Url = $Url
        ElementID = $elementId
        AppName = $appName
        Status = "Pass"
        StartTime = Get-Date
        EndTime = $null
        Duration = 0
        Tests = @()
        Errors = @()
        Warnings = @()
        Metrics = @{}
    }

    try {
        Write-Host "$MyTag Testing card: $Title ($elementId)" -ForegroundColor Cyan

        # Detect card type from tags and element ID
        $cardType = Get-CardType -ElementID $elementId -Tags $tags

        Write-Verbose "$MyTag Detected card type: $cardType"
        $testResult.Metrics.CardType = $cardType

        # Define validation rules based on card type
        $validationRules = Get-ValidationRules -CardType $cardType

        # Test 1: Basic load test
        Write-Verbose "$MyTag Running basic load test..."
        $loadTest = Test-DebugCardLoad `
            -Url $Url `
            -Title $Title `
            -SessionID $SessionID `
            -ValidationRules $validationRules `
            -CloseAfterTest:$false `
            -TimeoutSeconds $TimeoutSeconds

        $testResult.Tests += @{
            Name = "Basic Load Test"
            Result = $loadTest.Status
            Duration = $loadTest.Duration
            SubTests = $loadTest.Tests
        }

        if ($loadTest.Status -eq "Fail") {
            $testResult.Status = "Fail"
            $testResult.Errors += $loadTest.Errors
        } elseif ($loadTest.Status -eq "Warn" -and $testResult.Status -eq "Pass") {
            $testResult.Status = "Warn"
            $testResult.Warnings += $loadTest.Warnings
        }

        $cardId = $loadTest.CardID

        if (-not $cardId) {
            throw "Card ID not available - cannot continue testing"
        }

        # Wait for card to stabilize
        Start-Sleep -Milliseconds 1500

        # Test 2: Get card metrics
        Write-Verbose "$MyTag Collecting card metrics..."
        $enqueueScript = Join-Path $PSScriptRoot "Debug_Client_Command_Enqueue.ps1"
        $metricsResult = & $enqueueScript -Command "getCardMetrics" -Type predefined `
            -Params @{ cardId = $cardId } -SessionID $SessionID

        Start-Sleep -Milliseconds 1000

        try {
            $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET

            $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $metricsResult.CommandID } | Select-Object -First 1

            if ($historyEntry) {
                $metrics = $historyEntry.Result
                $testResult.Metrics.DOMNodes = $metrics.domNodeCount
                $testResult.Metrics.ErrorCount = $metrics.errorCount
                $testResult.Metrics.ScriptCount = $metrics.scriptCount
                $testResult.Metrics.ImageCount = $metrics.imageCount
                $testResult.Metrics.InputCount = $metrics.inputCount
                $testResult.Metrics.Dimensions = $metrics.dimensions
                $testResult.Metrics.IsVisible = $metrics.isVisible

                Write-Verbose "$MyTag Metrics: $($metrics.domNodeCount) nodes, $($metrics.errorCount) errors"
            }
        } catch {
            Write-Verbose "$MyTag Error polling history: $_"
        }

        # Test 3: Type-specific tests
        $typeTests = Invoke-TypeSpecificTests -CardType $cardType -CardID $cardId -SessionID $SessionID

        if ($typeTests.Count -gt 0) {
            $testResult.Tests += @{
                Name = "Type-Specific Tests ($cardType)"
                Result = ($typeTests | Where-Object { $_.Result -eq "Fail" }).Count -eq 0 ? "Pass" : "Warn"
                SubTests = $typeTests
            }

            # Update status based on type tests
            foreach ($test in $typeTests) {
                if ($test.Result -eq "Fail") {
                    $testResult.Warnings += "Type-specific test failed: $($test.Name)"
                    if ($testResult.Status -eq "Pass") { $testResult.Status = "Warn" }
                }
            }
        }

        # Test 4: Interactive elements detection
        Write-Verbose "$MyTag Detecting interactive elements..."
        $interactiveTests = @()

        $enqueueScript = Join-Path $PSScriptRoot "Debug_Client_Command_Enqueue.ps1"
        $buttonCheck = & $enqueueScript -Command "querySelectorAll" -Type predefined `
            -Params @{ selector = "button, [role='button']"; maxResults = 100 } -SessionID $SessionID

        Start-Sleep -Milliseconds 500

        try {
            $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET

            $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $buttonCheck.CommandID } | Select-Object -First 1

            if ($historyEntry) {
                $buttonCount = $historyEntry.Result.count
                $testResult.Metrics.ButtonCount = $buttonCount
                $interactiveTests += @{
                    Name = "Buttons"
                    Result = "Info"
                    Count = $buttonCount
                }
            }
        } catch {
            Write-Verbose "$MyTag Error polling history: $_"
        }

        if ($interactiveTests.Count -gt 0) {
            $testResult.Tests += @{
                Name = "Interactive Elements"
                Result = "Info"
                SubTests = $interactiveTests
            }
        }

    } catch {
        $testResult.Status = "Fail"
        $testResult.Errors += "Exception during test: $($_.Exception.Message)"
        Write-Error "$MyTag Test failed: $_"

    } finally {
        # Close card
        if ($cardId) {
            Write-Verbose "$MyTag Closing test card: $cardId"
            try {
                Close-DebugCard -CardID $cardId -SessionID $SessionID -Wait -TimeoutSeconds 5 | Out-Null
            } catch {
                Write-Warning "$MyTag Failed to close card: $_"
            }
        }

    # Finalize result
    $testResult.EndTime = Get-Date
    $testResult.Duration = ($testResult.EndTime - $testResult.StartTime).TotalSeconds

    # Summary
    Write-Host "$MyTag Test complete: $Title - Status: $($testResult.Status) - Duration: $([math]::Round($testResult.Duration, 2))s" `
        -ForegroundColor $(if ($testResult.Status -eq "Pass") { "Green" } elseif ($testResult.Status -eq "Warn") { "Yellow" } else { "Red" })
}

return $testResult

# Helper function: Detect card type
function Get-CardType {
    param($ElementID, $Tags)

    # Visualization cards
    if ($Tags -contains "visualization" -or $ElementID -match "chart|graph|heatmap|histogram|plot") {
        return "Visualization"
    }

    # File management cards
    if ($Tags -contains "files" -or $Tags -contains "storage" -or $ElementID -match "file|explorer|browser") {
        return "FileManagement"
    }

    # Database cards
    if ($Tags -contains "database" -or $ElementID -match "sql|db|query") {
        return "Database"
    }

    # Container management cards
    if ($Tags -contains "containers" -or $ElementID -match "docker|container|pod") {
        return "Container"
    }

    # Task management cards
    if ($Tags -contains "tasks" -or $ElementID -match "task|job|schedule") {
        return "TaskManagement"
    }

    # Debug cards
    if ($Tags -contains "debug" -or $ElementID -match "debug|console|log") {
        return "Debug"
    }

    # Monitoring cards
    if ($Tags -contains "monitoring" -or $Tags -contains "metrics" -or $ElementID -match "monitor|metric|stat") {
        return "Monitoring"
    }

    return "Generic"
}

# Helper function: Get validation rules by type
function Get-ValidationRules {
    param($CardType)

    $rules = @{
        RequiredElements = @(".card-header", ".card-content")
        ForbiddenErrors = @(".error", ".error-message")
        MaxLoadTimeMs = 10000
        RequireComponent = $true
    }

    switch ($CardType) {
        "Visualization" {
            $rules.RequiredElements += @("canvas", "svg")
            $rules.MaxLoadTimeMs = 8000
        }
        "FileManagement" {
            $rules.RequiredElements += @(".file-tree", "[class*='file']", "[class*='folder']")
            $rules.MaxLoadTimeMs = 6000
        }
        "Database" {
            $rules.RequiredElements += @("textarea", "[class*='query']", "table")
        }
        "Container" {
            $rules.RequiredElements += @("[class*='status']", "button")
        }
    }

    return $rules
}

# Helper function: Run type-specific tests
function Invoke-TypeSpecificTests {
    param($CardType, $CardID, $SessionID)

    $tests = @()

    $enqueueScript = Join-Path $PSScriptRoot "Debug_Client_Command_Enqueue.ps1"

    switch ($CardType) {
        "Visualization" {
            # Check for canvas or SVG elements
            $chartCheck = & $enqueueScript -Command "querySelector" -Type predefined `
                -Params @{ selector = "canvas, svg" } -SessionID $SessionID
            Start-Sleep -Milliseconds 500

            try {
                $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET

                $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $chartCheck.CommandID } | Select-Object -First 1

                if ($historyEntry) {
                    $tests += @{
                        Name = "Chart Element Present"
                        Result = $historyEntry.Result.found ? "Pass" : "Fail"
                    }
                }
            } catch {
                Write-Verbose "[Invoke-TypeSpecificTests] Error polling history: $_"
            }
        }

        "FileManagement" {
            # Check for file tree or list
            $fileTreeCheck = & $enqueueScript -Command "querySelector" -Type predefined `
                -Params @{ selector = ".file-tree, [class*='tree'], ul, table" } -SessionID $SessionID
            Start-Sleep -Milliseconds 500

            try {
                $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET

                $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $fileTreeCheck.CommandID } | Select-Object -First 1

                if ($historyEntry) {
                    $tests += @{
                        Name = "File Structure Present"
                        Result = $historyEntry.Result.found ? "Pass" : "Fail"
                    }
                }
            } catch {
                Write-Verbose "[Invoke-TypeSpecificTests] Error polling history: $_"
            }
        }

        "Debug" {
            # Check for console or log display
            $consoleCheck = & $enqueueScript -Command "querySelector" -Type predefined `
                -Params @{ selector = "textarea, pre, [class*='console'], [class*='log']" } -SessionID $SessionID
            Start-Sleep -Milliseconds 500

            try {
                $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET

                $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $consoleCheck.CommandID } | Select-Object -First 1

                if ($historyEntry) {
                    $tests += @{
                        Name = "Console Display Present"
                        Result = $historyEntry.Result.found ? "Pass" : "Fail"
                    }
                }
            } catch {
                Write-Verbose "[Invoke-TypeSpecificTests] Error polling history: $_"
            }
        }
    }

    return $tests
}
