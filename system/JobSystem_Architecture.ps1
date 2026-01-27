#Requires -Version 7

<#
.SYNOPSIS
    Job System Architecture - Global Structure Initialization

.DESCRIPTION
    Defines the new job system architecture:
    - Jobs stored in apps/[appname]/jobs/[JobName]/
    - Central command queue for job control
    - Role-based access control from job.json
    - Template variable substitution
#>

function Initialize-PSWebHostJobSystem {
    <#
    .SYNOPSIS
        Initializes the global job system structure
    #>
    [CmdletBinding()]
    param()

    if (-not $Global:PSWebServer.Jobs) {
        $Global:PSWebServer.Jobs = [hashtable]::Synchronized(@{
            # PowerShell background jobs
            Jobs = @()

            # Command queue for job operations
            CommandQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()

            # Discovered jobs from all apps
            Catalog = @{}

            # Running job tracking
            Running = [hashtable]::Synchronized(@{})

            # Job history/results
            History = @()
        })
    }

    Write-Verbose "[JobSystem] Initialized global job structure"
}

function Get-PSWebHostJobCatalog {
    <#
    .SYNOPSIS
        Discovers all jobs from apps/*/jobs/ directories

    .DESCRIPTION
        Scans all enabled apps for job definitions
        Returns catalog of available jobs with metadata
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = $Global:PSWebServer.Project_Root.Path
    )

    $catalog = @{}
    $appsDir = Join-Path $ProjectRoot "apps"

    if (-not (Test-Path $appsDir)) {
        Write-Warning "[JobSystem] Apps directory not found: $appsDir"
        return $catalog
    }

    # Scan each app
    $apps = Get-ChildItem -Path $appsDir -Directory

    foreach ($app in $apps) {
        $jobsDir = Join-Path $app.FullName "jobs"

        if (-not (Test-Path $jobsDir)) {
            continue
        }

        # Find all job directories (each contains job.json + script)
        $jobDirs = Get-ChildItem -Path $jobsDir -Directory

        foreach ($jobDir in $jobDirs) {
            $jobJsonPath = Join-Path $jobDir.FullName "job.json"

            if (-not (Test-Path $jobJsonPath)) {
                Write-Warning "[JobSystem] Missing job.json in: $($jobDir.FullName)"
                continue
            }

            try {
                # Load job metadata
                $jobJson = Get-Content -Path $jobJsonPath -Raw | ConvertFrom-Json

                # Build job ID (unique identifier)
                $jobId = "$($app.Name)/$($jobDir.Name)"

                $catalog[$jobId] = @{
                    JobID = $jobId
                    AppName = $app.Name
                    JobName = $jobDir.Name
                    Name = $jobJson.Name
                    Description = $jobJson.Description
                    ScriptPath = Join-Path $jobDir.FullName $jobJson.ScriptRelativePath
                    JobDirectory = $jobDir.FullName
                    Metadata = $jobJson
                    LastScanned = Get-Date
                }

                Write-Verbose "[JobSystem] Discovered job: $jobId"
            }
            catch {
                Write-Warning "[JobSystem] Failed to load job metadata from $jobJsonPath : $($_.Exception.Message)"
            }
        }
    }

    return $catalog
}

function Initialize-PSWebHostJob {
    <#
    .SYNOPSIS
        Initializes a job by running init-job.ps1 and parsing job.json with variable substitution

    .PARAMETER JobID
        The job identifier (AppName/JobName)

    .PARAMETER Variables
        Hashtable of variables for template substitution
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobID,

        [hashtable]$Variables = @{}
    )

    $catalog = $Global:PSWebServer.Jobs.Catalog

    if (-not $catalog.ContainsKey($JobID)) {
        throw "Job not found in catalog: $JobID"
    }

    $jobInfo = $catalog[$JobID]
    $jobDir = $jobInfo.JobDirectory

    # Run init-job.ps1 if it exists
    $initScript = Join-Path $jobDir "init-job.ps1"
    if (Test-Path $initScript) {
        Write-Verbose "[JobSystem] Running init script: $initScript"

        try {
            # Execute init script in current scope to populate variables
            . $initScript -Variables $Variables
        }
        catch {
            Write-Error "[JobSystem] Init script failed for $JobID : $($_.Exception.Message)"
            throw
        }
    }

    # Parse job.json with template substitution
    $jobJsonPath = Join-Path $jobDir "job.json"
    $jobJsonRaw = Get-Content -Path $jobJsonPath -Raw

    # Find all template variables {{VarName}}
    $templateVars = [regex]::Matches($jobJsonRaw, '\{\{(\w+)\}\}') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

    # Check for missing variables
    $missingVars = @()
    foreach ($varName in $templateVars) {
        if (-not $Variables.ContainsKey($varName)) {
            $missingVars += $varName
        }
    }

    if ($missingVars.Count -gt 0) {
        Write-Error "[JobSystem] Job $JobID requires variables that are not set: $($missingVars -join ', ')"
        throw "Missing required variables: $($missingVars -join ', ')"
    }

    # Perform substitution
    $jobJsonProcessed = $jobJsonRaw
    foreach ($varName in $templateVars) {
        $value = $Variables[$varName]
        $jobJsonProcessed = $jobJsonProcessed -replace "\{\{$varName\}\}", $value
    }

    # Parse processed JSON
    $jobMetadata = $jobJsonProcessed | ConvertFrom-Json

    return @{
        JobID = $JobID
        Metadata = $jobMetadata
        ScriptPath = Join-Path $jobDir $jobMetadata.ScriptRelativePath
        Variables = $Variables
    }
}

function Test-PSWebHostJobPermission {
    <#
    .SYNOPSIS
        Checks if user has permission to perform action on job

    .PARAMETER JobID
        The job identifier

    .PARAMETER Action
        Action to check: start, stop, restart

    .PARAMETER Roles
        User's roles
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobID,

        [Parameter(Mandatory)]
        [ValidateSet('start', 'stop', 'restart')]
        [string]$Action,

        [Parameter(Mandatory)]
        [string[]]$Roles
    )

    $catalog = $Global:PSWebServer.Jobs.Catalog

    if (-not $catalog.ContainsKey($JobID)) {
        return $false
    }

    $jobMetadata = $catalog[$JobID].Metadata

    # Get required roles for action
    $requiredRoles = switch ($Action) {
        'start' { $jobMetadata.roles_start }
        'stop' { $jobMetadata.roles_stop }
        'restart' { $jobMetadata.roles_restart }
    }

    if (-not $requiredRoles) {
        # No roles specified = allow all authenticated users
        return $true
    }

    # Check if user has any of the required roles
    foreach ($role in $Roles) {
        if ($requiredRoles -contains $role) {
            return $true
        }
    }

    return $false
}

Export-ModuleMember -Function @(
    'Initialize-PSWebHostJobSystem',
    'Get-PSWebHostJobCatalog',
    'Initialize-PSWebHostJob',
    'Test-PSWebHostJobPermission'
)
