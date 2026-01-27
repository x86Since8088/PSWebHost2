#Requires -Version 7

<#
.SYNOPSIS
    Creates a new job in an app's jobs folder

.DESCRIPTION
    Creates the directory structure and template files for a new job:
    - apps/[AppName]/jobs/[JobName]/
    - job.json with metadata
    - [JobName].ps1 script with -Test and -Roles parameters
    - Optional init-job.ps1 for initialization

.PARAMETER AppName
    The app name where the job will be created

.PARAMETER JobName
    The name of the job (used for directory and default script name)

.PARAMETER DisplayName
    The display name for the job (shown in UI)

.PARAMETER Description
    Description of what the job does

.PARAMETER ScriptName
    The script filename (default: [JobName].ps1)

.PARAMETER RolesStart
    Roles that can start the job (default: @('admin'))

.PARAMETER RolesStop
    Roles that can stop the job (default: @('admin'))

.PARAMETER RolesRestart
    Roles that can restart the job (default: @('admin'))

.PARAMETER DefaultSchedule
    Default schedule for the job (cron format or empty)

.PARAMETER CreateInitScript
    If specified, creates an init-job.ps1 template

.EXAMPLE
    .\TaskManagement_JobFolderInApp_New.ps1 -AppName "WebHostMetrics" -JobName "CollectMetrics" -DisplayName "Metrics Collection" -Description "Collects system metrics"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AppName,

    [Parameter(Mandatory)]
    [string]$JobName,

    [Parameter(Mandatory)]
    [string]$DisplayName,

    [Parameter(Mandatory)]
    [string]$Description,

    [string]$ScriptName,

    [string[]]$RolesStart = @('admin'),

    [string[]]$RolesStop = @('admin'),

    [string[]]$RolesRestart = @('admin'),

    [string]$DefaultSchedule = '',

    [switch]$CreateInitScript
)

$MyTag = '[TaskManagement:JobFolderInApp:New]'

try {
    # Get project root
    $projectRoot = if ($Global:PSWebServer.Project_Root.Path) {
        $Global:PSWebServer.Project_Root.Path
    } else {
        Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    # Validate app exists
    $appPath = Join-Path $projectRoot "apps\$AppName"
    if (-not (Test-Path $appPath)) {
        throw "App not found: $AppName (Path: $appPath)"
    }

    # Create jobs directory if it doesn't exist
    $jobsDir = Join-Path $appPath "jobs"
    if (-not (Test-Path $jobsDir)) {
        New-Item -Path $jobsDir -ItemType Directory -Force | Out-Null
        Write-Host "$MyTag Created jobs directory: $jobsDir" -ForegroundColor Green
    }

    # Create job directory
    $jobDir = Join-Path $jobsDir $JobName
    if (Test-Path $jobDir) {
        throw "Job already exists: $JobName (Path: $jobDir)"
    }

    New-Item -Path $jobDir -ItemType Directory -Force | Out-Null
    Write-Host "$MyTag Created job directory: $jobDir" -ForegroundColor Green

    # Determine script name
    if (-not $ScriptName) {
        $ScriptName = "$JobName.ps1"
    }

    # Create job.json
    $jobJson = @{
        Name = $DisplayName
        Description = $Description
        default_schedule = $DefaultSchedule
        ScriptRelativePath = $ScriptName
        argumentlist = @()
        roles_start = $RolesStart
        roles_stop = $RolesStop
        roles_restart = $RolesRestart
    }

    $jobJsonPath = Join-Path $jobDir "job.json"
    $jobJson | ConvertTo-Json -Depth 10 | Set-Content -Path $jobJsonPath -Encoding UTF8
    Write-Host "$MyTag Created job.json: $jobJsonPath" -ForegroundColor Green

    # Create job script template
    $scriptPath = Join-Path $jobDir $ScriptName
    $scriptTemplate = @"
#Requires -Version 7

<#
.SYNOPSIS
    $DisplayName

.DESCRIPTION
    $Description

.PARAMETER Test
    If specified, runs in test mode

.PARAMETER Roles
    User roles (auto-populated from security.json)

.PARAMETER Variables
    Hashtable of variables passed from job initialization
#>

[CmdletBinding()]
param(
    [switch]`$Test,
    [string[]]`$Roles = @(),
    [hashtable]`$Variables = @{}
)

`$MyTag = '[$AppName:Job:$JobName]'

try {
    # Use Write-Verbose for test mode commentary, Write-Host for normal mode
    if (`$Test) {
        Write-Verbose "`$MyTag Running in TEST mode"
    } else {
        Write-Host "`$MyTag Starting job..." -ForegroundColor Cyan
    }

    # Access variables
    # Example: `$myVar = if (`$Variables.ContainsKey('MyVariable')) {
    #     `$Variables['MyVariable']
    # } else {
    #     'default_value'
    # }

    # Test mode: Run once and return data to stdout
    if (`$Test) {
        # Perform test operations
        Write-Verbose "`$MyTag Performing test operations..."

        `$result = @{
            Success = `$true
            Message = "Test completed successfully"
            Data = @{
                # Add actual data here
                Example = "value"
            }
        }

        Write-Verbose "`$MyTag Test completed"

        # Output data to stdout (commentary goes to verbose stream)
        return `$result
    }

    # Normal mode: Continuous operation
    Write-Host "`$MyTag Running in NORMAL mode" -ForegroundColor Green

    while (`$true) {
        # Job logic here
        Write-Host "`$MyTag Performing job tasks..." -ForegroundColor Yellow

        # Example work
        Start-Sleep -Seconds 5
    }
}
catch {
    Write-Error "`$MyTag Job failed: `$_"

    if (`$Test) {
        # Output error data to stdout
        return @{
            Success = `$false
            Error = `$_.Exception.Message
        }
    }

    throw
}
"@

    Set-Content -Path $scriptPath -Value $scriptTemplate -Encoding UTF8
    Write-Host "$MyTag Created job script: $scriptPath" -ForegroundColor Green

    # Create init-job.ps1 if requested
    if ($CreateInitScript) {
        $initScriptPath = Join-Path $jobDir "init-job.ps1"
        $initScriptTemplate = @"
#Requires -Version 7

<#
.SYNOPSIS
    Initialization script for $DisplayName

.DESCRIPTION
    This script runs before job.json is parsed
    Use it to:
    - Validate environment
    - Set default variables
    - Perform pre-execution checks

.PARAMETER Variables
    Hashtable of variables that will be used for template substitution
#>

[CmdletBinding()]
param(
    [hashtable]`$Variables = @{}
)

`$MyTag = '[$AppName:Job:$JobName:Init]'

try {
    Write-Verbose "`$MyTag Running initialization..."

    # Example: Set default variable if not provided
    # if (-not `$Variables.ContainsKey('MyVariable')) {
    #     `$Variables['MyVariable'] = 'DefaultValue'
    # }

    # Example: Validate required variables
    # if (-not `$Variables.ContainsKey('RequiredVariable')) {
    #     throw "Required variable 'RequiredVariable' not provided"
    # }

    Write-Verbose "`$MyTag Initialization complete"
}
catch {
    Write-Error "`$MyTag Initialization failed: `$_"
    throw
}
"@

        Set-Content -Path $initScriptPath -Value $initScriptTemplate -Encoding UTF8
        Write-Host "$MyTag Created init script: $initScriptPath" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "$MyTag Job created successfully!" -ForegroundColor Green
    Write-Host "$MyTag JobID: $AppName/$JobName" -ForegroundColor Cyan
    Write-Host "$MyTag Location: $jobDir" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "$MyTag Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Edit the job script: $scriptPath" -ForegroundColor Gray
    Write-Host "  2. Update job.json if needed: $jobJsonPath" -ForegroundColor Gray
    if ($CreateInitScript) {
        Write-Host "  3. Customize init-job.ps1: $(Join-Path $jobDir 'init-job.ps1')" -ForegroundColor Gray
    }
    Write-Host "  4. Test the job: .\TaskManagement_AppJobFolder_Test.ps1 -AppName '$AppName' -JobName '$JobName'" -ForegroundColor Gray
    Write-Host ""

    return @{
        Success = $true
        AppName = $AppName
        JobName = $JobName
        JobID = "$AppName/$JobName"
        JobDirectory = $jobDir
        ScriptPath = $scriptPath
        JobJsonPath = $jobJsonPath
    }
}
catch {
    Write-Error "$MyTag $_"
    throw
}
