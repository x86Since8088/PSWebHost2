#Requires -Version 7

<#
.SYNOPSIS
    GET /apps/WebHostTaskManagement/api/v1/jobs/catalog

.DESCRIPTION
    Returns the catalog of available jobs from all apps
    Uses PSWebHost_Jobs module to discover jobs from apps/*/jobs/

.EXAMPLE
    GET /apps/WebHostTaskManagement/api/v1/jobs/catalog
#>

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata,
    [switch]$Test,
    [string[]]$Roles = @(),
    [hashtable]$Query = @{}
)

$MyTag = '[WebHostTaskManagement:API:Jobs:Catalog:Get]'

try {
    # Validate session
    if (-not $sessiondata.UserID) {
        throw "Unauthorized: No user ID in session"
    }

    # Get user roles for permission filtering
    $userRoles = $Roles
    if (-not $userRoles -or $userRoles.Count -eq 0) {
        $userRoles = @('authenticated')  # Default role for authenticated users
    }

    # Get job catalog from global structure (populated at server startup)
    $catalog = $Global:PSWebServer.Jobs.Catalog

    if (-not $catalog) {
        Write-Warning "$MyTag Job catalog not initialized. Attempting to load PSWebHost_Jobs module..."

        # Try to load module
        $modulePath = Join-Path $Global:PSWebServer.Project_Root.Path "modules\PSWebHost_Jobs\PSWebHost_Jobs.psd1"
        if (Test-Path $modulePath) {
            Import-Module $modulePath -DisableNameChecking -Force -ErrorAction Stop

            # Initialize and get catalog
            if (-not $Global:PSWebServer.Jobs) {
                Initialize-PSWebHostJobSystem
            }

            $catalog = Get-PSWebHostJobCatalog -ProjectRoot $Global:PSWebServer.Project_Root.Path
            $Global:PSWebServer.Jobs.Catalog = $catalog
        } else {
            throw "PSWebHost_Jobs module not found. Server may need restart."
        }
    }

    # Build job list with user permissions
    $jobs = @()

    foreach ($jobKey in $catalog.Keys) {
        $jobInfo = $catalog[$jobKey]
        $metadata = $jobInfo.Metadata

        # Check if user can start this job
        $canStart = $false
        $canStop = $false
        $canRestart = $false

        if ($metadata.roles_start) {
            foreach ($role in $userRoles) {
                if ($metadata.roles_start -contains $role) {
                    $canStart = $true
                    break
                }
            }
        } else {
            # No roles specified = all authenticated users can start
            $canStart = $true
        }

        if ($metadata.roles_stop) {
            foreach ($role in $userRoles) {
                if ($metadata.roles_stop -contains $role) {
                    $canStop = $true
                    break
                }
            }
        } else {
            $canStop = $true
        }

        if ($metadata.roles_restart) {
            foreach ($role in $userRoles) {
                if ($metadata.roles_restart -contains $role) {
                    $canRestart = $true
                    break
                }
            }
        } else {
            $canRestart = $true
        }

        # Check if job has init script
        $hasInitScript = Test-Path (Join-Path $jobInfo.JobDirectory "init-job.ps1")

        # Get template variables
        $templateVars = @()
        if ($metadata.template_variables) {
            foreach ($prop in $metadata.template_variables.PSObject.Properties) {
                $templateVars += @{
                    name = $prop.Name
                    description = $prop.Value
                }
            }
        }

        $jobs += @{
            jobId = $jobInfo.JobID
            appName = $jobInfo.AppName
            jobName = $jobInfo.JobName
            displayName = $jobInfo.Name
            description = $jobInfo.Description
            schedule = $metadata.default_schedule
            hasInitScript = $hasInitScript
            templateVariables = $templateVars
            permissions = @{
                canStart = $canStart
                canStop = $canStop
                canRestart = $canRestart
            }
            roles = @{
                start = $metadata.roles_start
                stop = $metadata.roles_stop
                restart = $metadata.roles_restart
            }
        }
    }

    # Sort by app name then job name
    $jobs = $jobs | Sort-Object -Property @{Expression={$_.appName}}, @{Expression={$_.jobName}}

    $response_data = @{
        success = $true
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        jobs = $jobs
        count = $jobs.Count
        userRoles = $userRoles
    }

    # Test mode
    if ($Test) {
        Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
        Write-Host "Status: 200 OK" -ForegroundColor Green
        $response_data | ConvertTo-Json -Depth 10 | Write-Host
        return
    }

    # Normal HTTP response
    $Response.StatusCode = 200
    $Response.ContentType = "application/json"
    $json = $response_data | ConvertTo-Json -Depth 10
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()

} catch {
    Write-Error "$MyTag $_"

    $error_response = @{
        success = $false
        error = $_.Exception.Message
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }

    if ($Test) {
        Write-Host "Status: 500 Internal Server Error" -ForegroundColor Red
        $error_response | ConvertTo-Json -Depth 10 | Write-Host
        return
    }

    $Response.StatusCode = 500
    $Response.ContentType = "application/json"
    $json = $error_response | ConvertTo-Json -Depth 10
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()
}
