<#
.SYNOPSIS
    Tests loading a single card with validation

.DESCRIPTION
    Launches a card, validates it loaded correctly, and optionally closes it.
    Performs basic health checks including DOM presence, component registration, and error detection.

.PARAMETER Url
    The card URL to test

.PARAMETER Title
    Optional title for the card (defaults to "Test Card")

.PARAMETER SessionID
    Target session ID. Defaults to "all".

.PARAMETER ValidationRules
    Hashtable of validation rules:
    - RequiredElements: Array of CSS selectors that must exist
    - ForbiddenErrors: Array of error selectors that must NOT exist
    - MaxLoadTimeMs: Maximum load time in milliseconds
    - RequireComponent: Boolean to check component registration

.PARAMETER CloseAfterTest
    If specified, closes the card after testing

.PARAMETER TimeoutSeconds
    Maximum time to wait for operations (default: 15 seconds)

.EXAMPLE
    Test-DebugCardLoad -Url "/apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer"

.EXAMPLE
    $rules = @{
        RequiredElements = @(".file-tree", ".toolbar")
        MaxLoadTimeMs = 5000
    }
    Test-DebugCardLoad -Url "/apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer" -ValidationRules $rules -CloseAfterTest

.OUTPUTS
    Returns test result object with status, duration, errors, and warnings
#>
[CmdletBinding()]
param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $false)]
        [string]$Title = "Test Card",

        [Parameter(Mandatory = $false)]
        [string]$SessionID = "all",

        [Parameter(Mandatory = $false)]
        [hashtable]$ValidationRules = @{
            RequiredElements = @(".card-header", ".card-content")
            ForbiddenErrors = @(".error", ".error-message")
            MaxLoadTimeMs = 10000
            RequireComponent = $true
        },

        [Parameter(Mandatory = $false)]
        [switch]$CloseAfterTest,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 15
    )

    $MyTag = '[Test-DebugCardLoad]'

    $testResult = @{
        Url = $Url
        Title = $Title
        Status = "Pass"
        StartTime = Get-Date
        EndTime = $null
        Duration = 0
        Tests = @()
        Errors = @()
        Warnings = @()
        CardID = $null
        ElementID = $null
    }

    try {
        Write-Verbose "$MyTag Testing card load: $Url"

        # Test 1: Launch card
        $launchStart = Get-Date
        $launchResult = Launch-DebugCard -Url $Url -Title $Title -SessionID $SessionID -Wait -TimeoutSeconds $TimeoutSeconds

        $launchDuration = ((Get-Date) - $launchStart).TotalMilliseconds

        if (-not $launchResult.Success) {
            $testResult.Status = "Fail"
            $testResult.Errors += "Failed to launch card: $($launchResult.Error)"
            $testResult.Tests += @{
                Name = "Launch"
                Result = "Fail"
                Duration = $launchDuration
                Error = $launchResult.Error
            }
            return $testResult
        }

        $testResult.Tests += @{
            Name = "Launch"
            Result = "Pass"
            Duration = $launchDuration
        }

        # Extract card info from result
        if ($launchResult.Result) {
            $testResult.CardID = $launchResult.Result.cardId
            $testResult.ElementID = $launchResult.Result.elementId
        }

        # Wait a moment for card to fully render
        Start-Sleep -Milliseconds 1000

        # Test 2: Validate card existence
        if ($testResult.CardID) {
            Write-Verbose "$MyTag Validating card: $($testResult.CardID)"

            $enqueueScript = Join-Path $PSScriptRoot "Debug_Client_Command_Enqueue.ps1"
            $validateResult = & $enqueueScript -Command "validateCard" -Type predefined `
                -Params @{ cardId = $testResult.CardID } -SessionID $SessionID

            if ($validateResult.Success) {
                # Wait for validation to complete
                Start-Sleep -Milliseconds 1000

                $validationData = $null
                try {
                    $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET

                    $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $validateResult.CommandID } | Select-Object -First 1

                    if ($historyEntry) {
                        $validationData = $historyEntry.Result
                    }
                } catch {
                    Write-Verbose "$MyTag Error polling history: $_"
                }

                if ($validationData) {
                    # Check validation results
                    $validationTests = @()

                    # DOM presence
                    if ($validationData.hasDOM) {
                        $validationTests += @{ Name = "DOM Present"; Result = "Pass" }
                    } else {
                        $validationTests += @{ Name = "DOM Present"; Result = "Fail" }
                        $testResult.Errors += "Card DOM not found"
                        $testResult.Status = "Fail"
                    }

                    # Component registration
                    if ($ValidationRules.RequireComponent -and -not $validationData.hasComponent) {
                        $validationTests += @{ Name = "Component Registered"; Result = "Fail" }
                        $testResult.Warnings += "Component not registered in window.cardComponents"
                        if ($testResult.Status -eq "Pass") { $testResult.Status = "Warn" }
                    } elseif ($ValidationRules.RequireComponent) {
                        $validationTests += @{ Name = "Component Registered"; Result = "Pass" }
                    }

                    # Error detection
                    if ($validationData.hasError) {
                        $validationTests += @{ Name = "No Errors"; Result = "Fail" }
                        $testResult.Errors += "Card contains $($validationData.errorCount) error elements"
                        $testResult.Status = "Fail"
                    } else {
                        $validationTests += @{ Name = "No Errors"; Result = "Pass" }
                    }

                    $testResult.Tests += @{
                        Name = "Validation"
                        Result = ($validationTests | Where-Object { $_.Result -eq "Fail" }).Count -eq 0 ? "Pass" : "Fail"
                        SubTests = $validationTests
                    }
                }
            }
        }

        # Test 3: Required elements check
        if ($ValidationRules.RequiredElements -and $ValidationRules.RequiredElements.Count -gt 0) {
            Write-Verbose "$MyTag Checking required elements..."

            $elementTests = @()
            $enqueueScript = Join-Path $PSScriptRoot "Debug_Client_Command_Enqueue.ps1"
            foreach ($selector in $ValidationRules.RequiredElements) {
                $queryResult = & $enqueueScript -Command "querySelector" -Type predefined `
                    -Params @{ selector = $selector } -SessionID $SessionID

                Start-Sleep -Milliseconds 500

                try {
                    $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET

                    $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $queryResult.CommandID } | Select-Object -First 1

                    if ($historyEntry -and $historyEntry.Result.found) {
                        $elementTests += @{ Name = "Element: $selector"; Result = "Pass" }
                    } else {
                        $elementTests += @{ Name = "Element: $selector"; Result = "Fail" }
                        $testResult.Warnings += "Required element not found: $selector"
                        if ($testResult.Status -eq "Pass") { $testResult.Status = "Warn" }
                    }
                } catch {
                    Write-Verbose "$MyTag Error polling history: $_"
                }
            }

            $testResult.Tests += @{
                Name = "Required Elements"
                Result = ($elementTests | Where-Object { $_.Result -eq "Fail" }).Count -eq 0 ? "Pass" : "Warn"
                SubTests = $elementTests
            }
        }

        # Test 4: Load time check
        if ($ValidationRules.MaxLoadTimeMs -and $launchDuration -gt $ValidationRules.MaxLoadTimeMs) {
            $testResult.Warnings += "Load time ${launchDuration}ms exceeds maximum ${$ValidationRules.MaxLoadTimeMs}ms"
            if ($testResult.Status -eq "Pass") { $testResult.Status = "Warn" }

            $testResult.Tests += @{
                Name = "Load Time"
                Result = "Warn"
                Duration = $launchDuration
                MaxAllowed = $ValidationRules.MaxLoadTimeMs
            }
        } else {
            $testResult.Tests += @{
                Name = "Load Time"
                Result = "Pass"
                Duration = $launchDuration
            }
        }

    } catch {
        $testResult.Status = "Fail"
        $testResult.Errors += "Exception during test: $($_.Exception.Message)"
        Write-Error "$MyTag Test failed: $_"

} finally {
    # Close card if requested
    if ($CloseAfterTest -and $testResult.CardID) {
        Write-Verbose "$MyTag Closing test card: $($testResult.CardID)"
        try {
            Close-DebugCard -CardID $testResult.CardID -SessionID $SessionID -Wait | Out-Null
        } catch {
            Write-Warning "$MyTag Failed to close card: $_"
        }
    }

    # Finalize result
    $testResult.EndTime = Get-Date
    $testResult.Duration = ($testResult.EndTime - $testResult.StartTime).TotalSeconds
}

return $testResult
