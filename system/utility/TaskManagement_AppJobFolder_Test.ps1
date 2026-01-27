#Requires -Version 7

<#
.SYNOPSIS
    Tests a job from an app's jobs folder

.DESCRIPTION
    Tests a job by:
    1. Validating job.json exists and is valid
    2. Running init-job.ps1 if it exists
    3. Validating template variables
    4. Executing the job script with -Test switch

.PARAMETER AppName
    The app name where the job is located

.PARAMETER JobName
    The name of the job to test

.PARAMETER Variables
    Hashtable of variables for template substitution

.PARAMETER Roles
    Roles to pass to the job script (default: @('admin'))

.PARAMETER SkipExecution
    If specified, only validates metadata without running the script

.EXAMPLE
    .\TaskManagement_AppJobFolder_Test.ps1 -AppName "WebHostMetrics" -JobName "CollectMetrics"

.EXAMPLE
    .\TaskManagement_AppJobFolder_Test.ps1 -AppName "WebHostMetrics" -JobName "CollectMetrics" -Variables @{Interval=60}

.EXAMPLE
    .\TaskManagement_AppJobFolder_Test.ps1 -AppName "WebHostMetrics" -JobName "CollectMetrics" -SkipExecution
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AppName,

    [Parameter(Mandatory)]
    [string]$JobName,

    [hashtable]$Variables = @{},

    [string[]]$Roles = @('admin'),

    [switch]$SkipExecution
)

$MyTag = '[TaskManagement:AppJobFolder:Test]'

try {
    # Get project root
    $projectRoot = if ($Global:PSWebServer.Project_Root.Path) {
        $Global:PSWebServer.Project_Root.Path
    } else {
        Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    Write-Host "$MyTag Testing job: $AppName/$JobName" -ForegroundColor Cyan
    Write-Host ""

    # Validate app exists
    $appPath = Join-Path $projectRoot "apps\$AppName"
    if (-not (Test-Path $appPath)) {
        throw "App not found: $AppName (Path: $appPath)"
    }
    Write-Host "[✓] App directory exists: $appPath" -ForegroundColor Green

    # Validate jobs directory exists
    $jobsDir = Join-Path $appPath "jobs"
    if (-not (Test-Path $jobsDir)) {
        throw "Jobs directory not found: $jobsDir"
    }
    Write-Host "[✓] Jobs directory exists: $jobsDir" -ForegroundColor Green

    # Validate job directory exists
    $jobDir = Join-Path $jobsDir $JobName
    if (-not (Test-Path $jobDir)) {
        throw "Job directory not found: $jobDir"
    }
    Write-Host "[✓] Job directory exists: $jobDir" -ForegroundColor Green

    # Validate job.json exists
    $jobJsonPath = Join-Path $jobDir "job.json"
    if (-not (Test-Path $jobJsonPath)) {
        throw "job.json not found: $jobJsonPath"
    }
    Write-Host "[✓] job.json exists: $jobJsonPath" -ForegroundColor Green

    # Parse job.json
    try {
        $jobJsonRaw = Get-Content -Path $jobJsonPath -Raw
        $jobJson = $jobJsonRaw | ConvertFrom-Json
        Write-Host "[✓] job.json is valid JSON" -ForegroundColor Green
    }
    catch {
        throw "job.json is invalid JSON: $_"
    }

    # Validate required fields
    $requiredFields = @('Name', 'Description', 'ScriptRelativePath')
    foreach ($field in $requiredFields) {
        if (-not $jobJson.$field) {
            throw "job.json missing required field: $field"
        }
    }
    Write-Host "[✓] job.json has all required fields" -ForegroundColor Green

    # Display job metadata
    Write-Host ""
    Write-Host "Job Metadata:" -ForegroundColor Yellow
    Write-Host "  Name: $($jobJson.Name)" -ForegroundColor Gray
    Write-Host "  Description: $($jobJson.Description)" -ForegroundColor Gray
    Write-Host "  Script: $($jobJson.ScriptRelativePath)" -ForegroundColor Gray
    Write-Host "  Default Schedule: $($jobJson.default_schedule)" -ForegroundColor Gray
    if ($jobJson.roles_start) {
        Write-Host "  Roles (Start): $($jobJson.roles_start -join ', ')" -ForegroundColor Gray
    }
    if ($jobJson.roles_stop) {
        Write-Host "  Roles (Stop): $($jobJson.roles_stop -join ', ')" -ForegroundColor Gray
    }
    if ($jobJson.roles_restart) {
        Write-Host "  Roles (Restart): $($jobJson.roles_restart -join ', ')" -ForegroundColor Gray
    }
    Write-Host ""

    # Check for init-job.ps1
    $initScriptPath = Join-Path $jobDir "init-job.ps1"
    if (Test-Path $initScriptPath) {
        Write-Host "[✓] init-job.ps1 exists: $initScriptPath" -ForegroundColor Green

        # Run init script
        try {
            Write-Host "[→] Running init-job.ps1..." -ForegroundColor Yellow
            . $initScriptPath -Variables $Variables
            Write-Host "[✓] init-job.ps1 completed successfully" -ForegroundColor Green
        }
        catch {
            throw "init-job.ps1 failed: $_"
        }
    } else {
        Write-Host "[i] No init-job.ps1 found (optional)" -ForegroundColor Gray
    }

    # Check for template variables in job.json
    $templateVars = [regex]::Matches($jobJsonRaw, '\{\{(\w+)\}\}') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

    if ($templateVars.Count -gt 0) {
        Write-Host ""
        Write-Host "Template Variables:" -ForegroundColor Yellow

        foreach ($varName in $templateVars) {
            if ($Variables.ContainsKey($varName)) {
                Write-Host "  [✓] $varName = $($Variables[$varName])" -ForegroundColor Green
            } else {
                Write-Host "  [✗] $varName = (NOT PROVIDED)" -ForegroundColor Red
            }
        }

        # Check for missing variables
        $missingVars = @()
        foreach ($varName in $templateVars) {
            if (-not $Variables.ContainsKey($varName)) {
                $missingVars += $varName
            }
        }

        if ($missingVars.Count -gt 0) {
            Write-Warning "Missing required variables: $($missingVars -join ', ')"
            Write-Host ""
            throw "Cannot proceed without required variables"
        }
    } else {
        Write-Host "[i] No template variables found in job.json" -ForegroundColor Gray
    }

    # Validate script exists
    $scriptPath = Join-Path $jobDir $jobJson.ScriptRelativePath
    if (-not (Test-Path $scriptPath)) {
        throw "Job script not found: $scriptPath"
    }
    Write-Host "[✓] Job script exists: $scriptPath" -ForegroundColor Green

    # Skip execution if requested
    if ($SkipExecution) {
        Write-Host ""
        Write-Host "$MyTag Validation complete (execution skipped)" -ForegroundColor Green
        return @{
            Success = $true
            ValidationOnly = $true
            JobID = "$AppName/$JobName"
            JobDirectory = $jobDir
            ScriptPath = $scriptPath
        }
    }

    # Execute the job script with -Test switch
    Write-Host ""
    Write-Host "[→] Executing job script with -Test switch..." -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

    try {
        $scriptContent = Get-Content -Path $scriptPath -Raw
        $scriptBlock = [scriptblock]::Create($scriptContent)

        # Prepare parameters
        $scriptParams = @{
            Test = $true
            Roles = $Roles
            Variables = $Variables
        }

        # Execute script
        $result = & $scriptBlock @scriptParams

        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
        Write-Host "[✓] Job script executed successfully" -ForegroundColor Green

        if ($result) {
            Write-Host ""
            Write-Host "Script Result:" -ForegroundColor Yellow
            $result | ConvertTo-Json -Depth 10 | Write-Host
        }
    }
    catch {
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
        throw "Job script execution failed: $_"
    }

    Write-Host ""
    Write-Host "$MyTag Test completed successfully!" -ForegroundColor Green
    Write-Host ""

    return @{
        Success = $true
        JobID = "$AppName/$JobName"
        JobDirectory = $jobDir
        ScriptPath = $scriptPath
        TestResult = $result
    }
}
catch {
    Write-Host ""
    Write-Error "$MyTag $_"
    throw
}
