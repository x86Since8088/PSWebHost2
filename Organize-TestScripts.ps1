#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Organizes test scripts from project root to appropriate locations
.DESCRIPTION
    Analyzes and moves test/diagnostic scripts to:
    - tests/ - General test scripts
    - tests/twin/ - Endpoint-specific twin tests
    - system/utility/ - Reusable diagnostic utilities
    - Removes obsolete scripts
#>

param(
    [switch]$DryRun,  # Show what would be done without doing it
    [switch]$Force    # Skip confirmation prompts
)

$rootPath = "C:\SC\PsWebHost"
$testsPath = Join-Path $rootPath "tests"
$twinPath = Join-Path $testsPath "twin"
$utilityPath = Join-Path $rootPath "system\utility"
$archivePath = Join-Path $testsPath "archive"

# Ensure target directories exist
@($testsPath, $twinPath, $archivePath) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

Write-Host "`n=== Test Script Organization ===" -ForegroundColor Cyan
Write-Host "Mode: $(if ($DryRun) { 'DRY RUN' } else { 'EXECUTE' })" -ForegroundColor Yellow
Write-Host ""

# Get all potential test scripts from root
$testPatterns = @('test*', 'check*', 'diagnose*', 'inspect*', 'measure*', 'query*', 'verify*', 'debug*', 'decode*', 'validate*', 'quick*')
$scripts = @()
foreach ($pattern in $testPatterns) {
    $scripts += Get-ChildItem -Path $rootPath -Filter "$pattern.ps1" -File -ErrorAction SilentlyContinue
}

# De-duplicate
$scripts = $scripts | Sort-Object FullName -Unique

Write-Host "Found $($scripts.Count) test/diagnostic scripts in root" -ForegroundColor Yellow
Write-Host ""

# Classification rules
$actions = @()

foreach ($script in $scripts) {
    $name = $script.Name
    $content = Get-Content $script.FullName -Raw -ErrorAction SilentlyContinue

    $action = @{
        Name = $name
        FullPath = $script.FullName
        Action = "Unknown"
        Destination = ""
        Reason = ""
    }

    # KEEP - Recently created utilities
    if ($name -match '^(Test-URLLayoutV2|Test-RunspaceModuleLoading|Quick-CheckExports|Check-ModuleExports|Validate-ModuleExports)\.ps1$') {
        $action.Action = "Move"
        $action.Destination = $testsPath
        $action.Reason = "Recent diagnostic utility - keep in tests/"
    }
    # KEEP - Job system tests
    elseif ($name -match '^Test-Job(Manipulation|SystemEndpoints)\.ps1$') {
        $action.Action = "Move"
        $action.Destination = Join-Path $testsPath "twin"
        $action.Reason = "Job system twin test"
    }
    # KEEP - Memory analysis
    elseif ($name -match '^Test-MemoryAnalysisWorkflow\.ps1$') {
        $action.Action = "Move"
        $action.Destination = $testsPath
        $action.Reason = "Memory analysis workflow test"
    }
    # OBSOLETE - Old metrics checks (replaced by Test-URLLayoutV2)
    elseif ($name -match '^(check_metrics|diagnose_metrics|test_metrics|start_and_verify_metrics)') {
        $action.Action = "Delete"
        $action.Reason = "Obsolete metrics diagnostic (superseded by newer tests)"
    }
    # OBSOLETE - Query/measure scripts (one-time diagnostics)
    elseif ($name -match '^(query_|measure_|inspect_)') {
        $action.Action = "Delete"
        $action.Reason = "One-time diagnostic script (no longer needed)"
    }
    # OBSOLETE - Job diagnostics (replaced by proper tests)
    elseif ($name -match '^(debug_job|diagnose_job|test_collectmetrics)') {
        $action.Action = "Delete"
        $action.Reason = "Old job diagnostic (superseded)"
    }
    # OBSOLETE - Server state checks (one-time use)
    elseif ($name -match '^(check_server|check_pswebserver|quick_status)') {
        $action.Action = "Delete"
        $action.Reason = "One-time server check (no longer needed)"
    }
    # OBSOLETE - Test scripts (replaced)
    elseif ($name -match '^test_(cli_simple|direct|server_response|via_cli)') {
        $action.Action = "Delete"
        $action.Reason = "Old test script (superseded by proper tests)"
    }
    # KEEP - Decode utility (useful)
    elseif ($name -eq 'decode_url.ps1') {
        $action.Action = "Move"
        $action.Destination = $utilityPath
        $action.Reason = "Useful URL decoding utility"
    }
    # KEEP - Module checks (recent)
    elseif ($name -match '^check.*module') {
        $action.Action = "Move"
        $action.Destination = $testsPath
        $action.Reason = "Module diagnostic utility"
    }
    # KEEP - FileExplorer config test
    elseif ($name -eq 'test_fileexplorer_config.ps1') {
        $action.Action = "Move"
        $action.Destination = Join-Path $testsPath "twin"
        $action.Reason = "FileExplorer configuration test"
    }
    # KEEP - User:others test
    elseif ($name -match 'test_user_others') {
        $action.Action = "Move"
        $action.Destination = Join-Path $testsPath "twin"
        $action.Reason = "User:others feature test"
    }
    # KEEP - Create test token
    elseif ($name -eq 'Create-TestAdminToken.ps1') {
        $action.Action = "Move"
        $action.Destination = $utilityPath
        $action.Reason = "Test token creation utility"
    }
    # KEEP - Test menu
    elseif ($name -match 'test-menu') {
        $action.Action = "Move"
        $action.Destination = Join-Path $testsPath "twin"
        $action.Reason = "Menu system test"
    }
    # KEEP - Browser/discover tests
    elseif ($name -match 'test-(browser|discover|final)') {
        $action.Action = "Move"
        $action.Destination = $testsPath
        $action.Reason = "Integration test"
    }
    # OBSOLETE - Runspace/memory diagnostics (one-time)
    elseif ($name -match 'diagnose_(runspace|memory)') {
        $action.Action = "Delete"
        $action.Reason = "One-time diagnostic (issue resolved)"
    }
    # KEEP - Check paths/service (might be useful)
    elseif ($name -match 'check-(paths|service)') {
        $action.Action = "Move"
        $action.Destination = $testsPath
        $action.Reason = "System check utility"
    }
    # OBSOLETE - Other check scripts
    else {
        # Default: Archive for review
        $action.Action = "Archive"
        $action.Destination = $archivePath
        $action.Reason = "Uncertain relevance - archive for review"
    }

    $actions += [PSCustomObject]$action
}

# Display plan
Write-Host "=== Organization Plan ===" -ForegroundColor Cyan
Write-Host ""

$grouped = $actions | Group-Object -Property Action

foreach ($group in $grouped) {
    $color = switch ($group.Name) {
        "Move" { "Green" }
        "Delete" { "Red" }
        "Archive" { "Yellow" }
        default { "Gray" }
    }

    Write-Host "$($group.Name): $($group.Count) scripts" -ForegroundColor $color
    foreach ($item in $group.Group) {
        Write-Host "  $($item.Name)" -ForegroundColor Gray
        Write-Host "    → $($item.Reason)" -ForegroundColor DarkGray
        if ($item.Destination) {
            Write-Host "    → $($item.Destination)" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}

# Execute or dry run
if ($DryRun) {
    Write-Host "DRY RUN - No changes made" -ForegroundColor Yellow
    exit 0
}

if (-not $Force) {
    $response = Read-Host "`nExecute this plan? (y/n)"
    if ($response -ne 'y') {
        Write-Host "Cancelled" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "`n=== Executing ===" -ForegroundColor Cyan

foreach ($action in $actions) {
    $name = $action.Name

    try {
        switch ($action.Action) {
            "Move" {
                $dest = Join-Path $action.Destination $name
                Write-Host "Moving $name → $($action.Destination)" -ForegroundColor Green
                Move-Item -Path $action.FullPath -Destination $dest -Force
            }
            "Delete" {
                Write-Host "Deleting $name" -ForegroundColor Red
                Remove-Item -Path $action.FullPath -Force
            }
            "Archive" {
                $dest = Join-Path $action.Destination $name
                Write-Host "Archiving $name" -ForegroundColor Yellow
                Move-Item -Path $action.FullPath -Destination $dest -Force
            }
        }
    } catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Moved: $(($actions | Where-Object Action -eq 'Move').Count)" -ForegroundColor Green
Write-Host "Deleted: $(($actions | Where-Object Action -eq 'Delete').Count)" -ForegroundColor Red
Write-Host "Archived: $(($actions | Where-Object Action -eq 'Archive').Count)" -ForegroundColor Yellow
Write-Host ""
Write-Host "✓ Organization complete" -ForegroundColor Green
Write-Host ""
Write-Host "Review archived scripts in: $archivePath" -ForegroundColor Yellow
