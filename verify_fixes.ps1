#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Verifies that the module conflict fixes and UI updates are working

.DESCRIPTION
    Tests:
    1. PSWebHost_Jobs module is loaded
    2. Job catalog endpoint works
    3. UI endpoint returns correct format
    4. No old job system errors
#>

param(
    [string]$ServerUrl = "http://localhost:8080"
)

Write-Host "`n=== PSWebHost Fix Verification ===" -ForegroundColor Cyan
Write-Host "Testing against: $ServerUrl`n" -ForegroundColor Gray

$results = @{
    Passed = 0
    Failed = 0
    Tests = @()
}

function Test-Result {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )

    $status = if ($Passed) { "✅ PASS" } else { "❌ FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }

    Write-Host "$status - $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "      $Message" -ForegroundColor Gray
    }

    if ($Passed) { $script:results.Passed++ } else { $script:results.Failed++ }
    $script:results.Tests += @{ Name = $TestName; Passed = $Passed; Message = $Message }
}

# Test 1: Check if PSWebHost_Jobs module is loaded
Write-Host "`n[1/6] Checking PSWebHost_Jobs module..." -ForegroundColor Yellow
try {
    $jobsModule = Get-Module -Name PSWebHost_Jobs
    if ($jobsModule) {
        Test-Result "PSWebHost_Jobs module loaded" $true "Version: $($jobsModule.Version)"
    } else {
        Test-Result "PSWebHost_Jobs module loaded" $false "Module not found in session"
    }
} catch {
    Test-Result "PSWebHost_Jobs module loaded" $false $_.Exception.Message
}

# Test 2: Check if old job system is NOT loaded
Write-Host "`n[2/6] Checking old job system removed..." -ForegroundColor Yellow
try {
    $oldModule = Get-Module -Name PSWebHost_JobExecution
    if (-not $oldModule) {
        Test-Result "Old PSWebHost_JobExecution NOT loaded" $true "Conflict avoided"
    } else {
        Test-Result "Old PSWebHost_JobExecution NOT loaded" $false "Old module still loaded - may cause conflicts"
    }
} catch {
    Test-Result "Old PSWebHost_JobExecution NOT loaded" $true "Module not found (good)"
}

# Test 3: Test UI endpoint format
Write-Host "`n[3/6] Testing UI endpoint format..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$ServerUrl/apps/WebHostTaskManagement/api/v1/ui/elements/task-manager" -Method GET

    # Check for new format
    $hasStatus = $null -ne $response.status
    $hasScriptPath = $null -ne $response.scriptPath
    $hasElement = $null -ne $response.element
    $hasElementId = $null -ne $response.element.id
    $hasElementComponent = $null -ne $response.element.component

    $correctFormat = $hasStatus -and $hasScriptPath -and $hasElement -and $hasElementId -and $hasElementComponent

    if ($correctFormat) {
        Test-Result "UI endpoint uses correct format" $true "Has status, scriptPath, and element object"
    } else {
        $missing = @()
        if (-not $hasStatus) { $missing += "status" }
        if (-not $hasScriptPath) { $missing += "scriptPath" }
        if (-not $hasElement) { $missing += "element" }
        if (-not $hasElementId) { $missing += "element.id" }
        if (-not $hasElementComponent) { $missing += "element.component" }
        Test-Result "UI endpoint uses correct format" $false "Missing: $($missing -join ', ')"
    }
} catch {
    Test-Result "UI endpoint uses correct format" $false $_.Exception.Message
}

# Test 4: Test job catalog endpoint
Write-Host "`n[4/6] Testing job catalog endpoint..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$ServerUrl/apps/WebHostTaskManagement/api/v1/jobs/catalog" -Method GET

    $hasSuccess = $response.success -eq $true
    $hasJobs = $null -ne $response.jobs
    $jobsIsArray = $response.jobs -is [Array]

    if ($hasSuccess -and $hasJobs -and $jobsIsArray) {
        Test-Result "Job catalog endpoint works" $true "Found $($response.jobs.Count) jobs"

        # Show job details if any exist
        if ($response.jobs.Count -gt 0) {
            Write-Host "      Jobs discovered:" -ForegroundColor Gray
            foreach ($job in $response.jobs) {
                Write-Host "        - $($job.displayName) ($($job.jobId))" -ForegroundColor Gray
                if ($job.templateVariables -and $job.templateVariables.Count -gt 0) {
                    Write-Host "          Variables: $($job.templateVariables.name -join ', ')" -ForegroundColor DarkGray
                }
            }
        }
    } else {
        $issues = @()
        if (-not $hasSuccess) { $issues += "success=false" }
        if (-not $hasJobs) { $issues += "no jobs property" }
        if (-not $jobsIsArray) { $issues += "jobs is not array" }
        Test-Result "Job catalog endpoint works" $false ($issues -join ', ')
    }
} catch {
    Test-Result "Job catalog endpoint works" $false $_.Exception.Message
}

# Test 5: Check global job state structure
Write-Host "`n[5/6] Checking global job state..." -ForegroundColor Yellow
try {
    $hasJobsState = $null -ne $Global:PSWebServer.Jobs
    $hasCatalog = $null -ne $Global:PSWebServer.Jobs.Catalog
    $hasCommandQueue = $null -ne $Global:PSWebServer.Jobs.CommandQueue
    $hasRunningJobs = $null -ne $Global:PSWebServer.Jobs.RunningJobs

    if ($hasJobsState -and $hasCatalog -and $hasCommandQueue -and $hasRunningJobs) {
        $catalogCount = $Global:PSWebServer.Jobs.Catalog.Count
        Test-Result "Job system state initialized" $true "Catalog has $catalogCount jobs"
    } else {
        $missing = @()
        if (-not $hasJobsState) { $missing += '$Global:PSWebServer.Jobs' }
        if (-not $hasCatalog) { $missing += 'Catalog' }
        if (-not $hasCommandQueue) { $missing += 'CommandQueue' }
        if (-not $hasRunningJobs) { $missing += 'RunningJobs' }
        Test-Result "Job system state initialized" $false "Missing: $($missing -join ', ')"
    }
} catch {
    Test-Result "Job system state initialized" $false $_.Exception.Message
}

# Test 6: Check for main_loop.ps1 scriptblock caching
Write-Host "`n[6/6] Checking main_loop.ps1 caching..." -ForegroundColor Yellow
try {
    $hasAppsState = $null -ne $Global:PSWebServer.Apps

    if ($hasAppsState) {
        $taskMgmtApp = $Global:PSWebServer.Apps['WebHostTaskManagement']

        if ($taskMgmtApp) {
            $hasScriptBlocks = $null -ne $taskMgmtApp['ScriptBlocks']
            $hasMainLoop = $null -ne $taskMgmtApp['ScriptBlocks']['MainLoop']
            $hasCode = $null -ne $taskMgmtApp['ScriptBlocks']['MainLoop']['Code']

            if ($hasScriptBlocks -and $hasMainLoop -and $hasCode) {
                $lastWriteTime = $taskMgmtApp['ScriptBlocks']['MainLoop']['LastWriteTime']
                Test-Result "main_loop.ps1 scriptblock cached" $true "Cached at: $lastWriteTime"
            } else {
                Test-Result "main_loop.ps1 scriptblock cached" $false "Scriptblock structure not complete"
            }
        } else {
            Test-Result "main_loop.ps1 scriptblock cached" $false "WebHostTaskManagement app not in Apps state"
        }
    } else {
        Test-Result "main_loop.ps1 scriptblock cached" $false '$Global:PSWebServer.Apps not initialized'
    }
} catch {
    Test-Result "main_loop.ps1 scriptblock cached" $false $_.Exception.Message
}

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Total Tests: $($results.Passed + $results.Failed)" -ForegroundColor Gray
Write-Host "Passed: $($results.Passed)" -ForegroundColor Green
Write-Host "Failed: $($results.Failed)" -ForegroundColor $(if ($results.Failed -gt 0) { "Red" } else { "Green" })

if ($results.Failed -eq 0) {
    Write-Host "`n🎉 All tests passed! System is working correctly." -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "  1. Navigate to http://localhost:8080" -ForegroundColor Gray
    Write-Host "  2. Open the Task Management card" -ForegroundColor Gray
    Write-Host "  3. Test the Job Catalog view" -ForegroundColor Gray
    Write-Host "  4. Try starting a job with template variables" -ForegroundColor Gray
} else {
    Write-Host "`n⚠️  Some tests failed. Review errors above." -ForegroundColor Yellow
}

Write-Host ""
