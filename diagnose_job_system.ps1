#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Diagnoses job system status and module loading

.DESCRIPTION
    Checks:
    - Which modules are loaded
    - Which job system is active
    - Global state structures
    - API endpoint configuration
#>

Write-Host "`n=== PSWebHost Job System Diagnostics ===" -ForegroundColor Cyan
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" -ForegroundColor Gray

# Check 1: Module Loading Status
Write-Host "[1/7] Checking loaded modules..." -ForegroundColor Yellow

$pswebhostJobs = Get-Module -Name PSWebHost_Jobs
$pswebhostJobExecution = Get-Module -Name PSWebHost_JobExecution
$pswebhostTasks = Get-Module -Name PSWebHostTasks

Write-Host "  PSWebHost_Jobs:         " -NoNewline
if ($pswebhostJobs) {
    Write-Host "✅ LOADED (v$($pswebhostJobs.Version))" -ForegroundColor Green
} else {
    Write-Host "❌ NOT LOADED" -ForegroundColor Red
}

Write-Host "  PSWebHost_JobExecution: " -NoNewline
if ($pswebhostJobExecution) {
    Write-Host "⚠️  LOADED (OLD SYSTEM - should be removed)" -ForegroundColor Yellow
} else {
    Write-Host "✅ NOT LOADED (good - old system)" -ForegroundColor Green
}

Write-Host "  PSWebHostTasks:         " -NoNewline
if ($pswebhostTasks) {
    Write-Host "✅ LOADED" -ForegroundColor Green
} else {
    Write-Host "⚠️  NOT LOADED" -ForegroundColor Yellow
}

# Check 2: Global State Structures
Write-Host "`n[2/7] Checking global state structures..." -ForegroundColor Yellow

Write-Host "  `$Global:PSWebServer.Jobs:        " -NoNewline
if ($Global:PSWebServer.Jobs) {
    Write-Host "✅ EXISTS" -ForegroundColor Green
    Write-Host "    - Catalog:       $($Global:PSWebServer.Jobs.Catalog.Count) jobs" -ForegroundColor Gray
    Write-Host "    - RunningJobs:   $($Global:PSWebServer.Jobs.RunningJobs.Count) active" -ForegroundColor Gray
    Write-Host "    - CommandQueue:  $(if ($Global:PSWebServer.Jobs.CommandQueue) { 'Initialized' } else { 'Missing' })" -ForegroundColor Gray
} else {
    Write-Host "❌ MISSING (new system not initialized)" -ForegroundColor Red
}

Write-Host "  `$Global:PSWebServer.Tasks:       " -NoNewline
if ($Global:PSWebServer.Tasks) {
    Write-Host "✅ EXISTS" -ForegroundColor Green
} else {
    Write-Host "❌ MISSING" -ForegroundColor Red
}

Write-Host "  `$Global:PSWebServer.RunningJobs: " -NoNewline
if ($Global:PSWebServer.RunningJobs) {
    Write-Host "⚠️  EXISTS ($($Global:PSWebServer.RunningJobs.Count) jobs - old system)" -ForegroundColor Yellow
} else {
    Write-Host "✅ NOT PRESENT (good)" -ForegroundColor Green
}

# Check 3: Module Functions Available
Write-Host "`n[3/7] Checking module functions..." -ForegroundColor Yellow

$newFunctions = @(
    'Initialize-PSWebHostJobSystem',
    'Get-PSWebHostJobCatalog',
    'Start-PSWebHostJob',
    'Stop-PSWebHostJob',
    'Process-PSWebHostJobCommandQueue'
)

$oldFunctions = @(
    'Submit-PSWebHostJob',
    'Process-PSWebHostJobSubmissions'
)

Write-Host "  New Job System Functions:" -ForegroundColor Cyan
foreach ($func in $newFunctions) {
    Write-Host "    $func : " -NoNewline
    if (Get-Command $func -ErrorAction SilentlyContinue) {
        Write-Host "✅" -ForegroundColor Green
    } else {
        Write-Host "❌" -ForegroundColor Red
    }
}

Write-Host "  Old Job System Functions:" -ForegroundColor Cyan
foreach ($func in $oldFunctions) {
    Write-Host "    $func : " -NoNewline
    if (Get-Command $func -ErrorAction SilentlyContinue) {
        Write-Host "⚠️  Present (should not be loaded)" -ForegroundColor Yellow
    } else {
        Write-Host "✅ Not present" -ForegroundColor Green
    }
}

# Check 4: Job Catalog
Write-Host "`n[4/7] Checking job catalog..." -ForegroundColor Yellow

if ($Global:PSWebServer.Jobs.Catalog) {
    Write-Host "  Job catalog contains $($Global:PSWebServer.Jobs.Catalog.Count) jobs:" -ForegroundColor Cyan

    foreach ($jobKey in $Global:PSWebServer.Jobs.Catalog.Keys) {
        $job = $Global:PSWebServer.Jobs.Catalog[$jobKey]
        Write-Host "    - $($job.JobID)" -ForegroundColor Gray
        Write-Host "      Name: $($job.Name)" -ForegroundColor DarkGray
        Write-Host "      App:  $($job.AppName)" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  ❌ No job catalog found" -ForegroundColor Red
}

# Check 5: App Main Loop Scriptblocks
Write-Host "`n[5/7] Checking app main_loop.ps1 caching..." -ForegroundColor Yellow

if ($Global:PSWebServer.Apps) {
    Write-Host "  Apps structure exists" -ForegroundColor Cyan

    $taskMgmt = $Global:PSWebServer.Apps['WebHostTaskManagement']
    if ($taskMgmt) {
        Write-Host "  WebHostTaskManagement app found:" -ForegroundColor Cyan

        $hasScriptBlocks = $taskMgmt['ScriptBlocks']
        $hasMainLoop = $taskMgmt['ScriptBlocks']['MainLoop']
        $hasCode = $taskMgmt['ScriptBlocks']['MainLoop']['Code']

        Write-Host "    - ScriptBlocks:    $(if ($hasScriptBlocks) { '✅' } else { '❌' })" -ForegroundColor $(if ($hasScriptBlocks) { 'Green' } else { 'Red' })
        Write-Host "    - MainLoop:        $(if ($hasMainLoop) { '✅' } else { '❌' })" -ForegroundColor $(if ($hasMainLoop) { 'Green' } else { 'Red' })
        Write-Host "    - Code cached:     $(if ($hasCode) { '✅' } else { '❌' })" -ForegroundColor $(if ($hasCode) { 'Green' } else { 'Red' })

        if ($hasMainLoop) {
            $lastWrite = $taskMgmt['ScriptBlocks']['MainLoop']['LastWriteTime']
            Write-Host "    - Last cached:     $lastWrite" -ForegroundColor Gray
        }
    } else {
        Write-Host "  ❌ WebHostTaskManagement app not found in Apps structure" -ForegroundColor Red
    }
} else {
    Write-Host "  ❌ `$Global:PSWebServer.Apps not initialized" -ForegroundColor Red
}

# Check 6: API Endpoints
Write-Host "`n[6/7] Testing API endpoints..." -ForegroundColor Yellow

try {
    $catalogResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/catalog" -Method GET -ErrorAction Stop

    Write-Host "  Job Catalog Endpoint:" -ForegroundColor Cyan
    Write-Host "    - Status:   $(if ($catalogResponse.success) { '✅ Success' } else { '❌ Failed' })" -ForegroundColor $(if ($catalogResponse.success) { 'Green' } else { 'Red' })
    Write-Host "    - Jobs:     $($catalogResponse.jobs.Count)" -ForegroundColor Gray

    if ($catalogResponse.jobs.Count -gt 0) {
        Write-Host "    - Job IDs:" -ForegroundColor Gray
        foreach ($job in $catalogResponse.jobs) {
            Write-Host "      * $($job.jobId)" -ForegroundColor DarkGray
        }
    }
} catch {
    Write-Host "  ❌ Failed to query catalog endpoint: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

try {
    $jobsResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs" -Method GET -ErrorAction Stop

    Write-Host "  Jobs Status Endpoint:" -ForegroundColor Cyan
    Write-Host "    - Status:   $(if ($jobsResponse.success) { '✅ Success' } else { '❌ Failed' })" -ForegroundColor $(if ($jobsResponse.success) { 'Green' } else { 'Red' })

    if ($jobsResponse.note) {
        Write-Host "    - Note:     " -NoNewline
        if ($jobsResponse.note -like "*legacy*") {
            Write-Host "⚠️  $($jobsResponse.note)" -ForegroundColor Yellow
        } else {
            Write-Host "$($jobsResponse.note)" -ForegroundColor Gray
        }
    }

    Write-Host "    - Running:  $($jobsResponse.jobs.running.Count)" -ForegroundColor Gray
    Write-Host "    - Pending:  $($jobsResponse.jobs.pending.Count)" -ForegroundColor Gray
    Write-Host "    - Complete: $($jobsResponse.jobs.completed.Count)" -ForegroundColor Gray
} catch {
    Write-Host "  ❌ Failed to query jobs endpoint: $($_.Exception.Message)" -ForegroundColor Red
}

# Check 7: Module Files
Write-Host "`n[7/7] Checking module files on disk..." -ForegroundColor Yellow

$moduleFiles = @{
    'PSWebHost_Jobs' = 'C:\SC\PsWebHost\modules\PSWebHost_Jobs\PSWebHost_Jobs.psd1'
    'PSWebHost_JobExecution' = 'C:\SC\PsWebHost\modules\PSWebHost_JobExecution\PSWebHost_JobExecution.psd1'
    'PSWebHostTasks' = 'C:\SC\PsWebHost\modules\PSWebHostTasks\PSWebHostTasks.psm1'
}

foreach ($moduleName in $moduleFiles.Keys) {
    $path = $moduleFiles[$moduleName]
    Write-Host "  $moduleName : " -NoNewline
    if (Test-Path $path) {
        Write-Host "✅ Found at $path" -ForegroundColor Green
    } else {
        Write-Host "❌ Not found at $path" -ForegroundColor Red
    }
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan

$usingNewSystem = $null -ne $pswebhostJobs -and $null -ne $Global:PSWebServer.Jobs
$usingOldSystem = $null -ne $pswebhostJobExecution -or $null -ne $Global:PSWebServer.RunningJobs

if ($usingNewSystem -and -not $usingOldSystem) {
    Write-Host "✅ NEW JOB SYSTEM ACTIVE" -ForegroundColor Green
    Write-Host "   - PSWebHost_Jobs module loaded" -ForegroundColor Gray
    Write-Host "   - Job catalog initialized with $($Global:PSWebServer.Jobs.Catalog.Count) jobs" -ForegroundColor Gray
    Write-Host "   - Old system not loaded" -ForegroundColor Gray
    Write-Host "`n🎉 System is configured correctly!" -ForegroundColor Green
} elseif ($usingOldSystem -and -not $usingNewSystem) {
    Write-Host "⚠️  OLD JOB SYSTEM STILL ACTIVE" -ForegroundColor Yellow
    Write-Host "   - PSWebHost_JobExecution module is loaded" -ForegroundColor Gray
    Write-Host "   - PSWebHost_Jobs module NOT loaded" -ForegroundColor Gray
    Write-Host "`n❌ Server needs to be restarted" -ForegroundColor Red
    Write-Host "   Run: Stop server (Ctrl+C) and restart with .\WebHost.ps1" -ForegroundColor Yellow
} elseif ($usingNewSystem -and $usingOldSystem) {
    Write-Host "⚠️  BOTH SYSTEMS LOADED (CONFLICT)" -ForegroundColor Yellow
    Write-Host "   - Both old and new job systems are active" -ForegroundColor Gray
    Write-Host "   - This can cause unexpected behavior" -ForegroundColor Gray
    Write-Host "`n❌ Server needs to be restarted" -ForegroundColor Red
    Write-Host "   Run: Stop server (Ctrl+C) and restart with .\WebHost.ps1" -ForegroundColor Yellow
} else {
    Write-Host "❌ NO JOB SYSTEM ACTIVE" -ForegroundColor Red
    Write-Host "   - Neither old nor new job system is loaded" -ForegroundColor Gray
    Write-Host "`n❌ Check module loading in WebHost.ps1" -ForegroundColor Red
}

Write-Host ""
