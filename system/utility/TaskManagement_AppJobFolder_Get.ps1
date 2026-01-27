#Requires -Version 7

<#
.SYNOPSIS
    Lists all jobs from apps/*/jobs/ directories

.DESCRIPTION
    Discovers and displays all available jobs across all apps
    Shows job metadata, permissions, and location information

.PARAMETER AppName
    Optional: Filter jobs by specific app name

.PARAMETER Format
    Output format: Table, List, Json, or Grid (default: Table)

.PARAMETER IncludeDisabled
    If specified, includes jobs from disabled apps

.EXAMPLE
    .\TaskManagement_AppJobFolder_Get.ps1

.EXAMPLE
    .\TaskManagement_AppJobFolder_Get.ps1 -AppName "WebHostMetrics"

.EXAMPLE
    .\TaskManagement_AppJobFolder_Get.ps1 -Format Json

.EXAMPLE
    .\TaskManagement_AppJobFolder_Get.ps1 -Format Grid
#>

[CmdletBinding()]
param(
    [string]$AppName,

    [ValidateSet('Table', 'List', 'Json', 'Grid')]
    [string]$Format = 'Table',

    [switch]$IncludeDisabled
)

$MyTag = '[TaskManagement:AppJobFolder:Get]'

try {
    # Get project root
    $projectRoot = if ($Global:PSWebServer.Project_Root.Path) {
        $Global:PSWebServer.Project_Root.Path
    } else {
        Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    Write-Verbose "$MyTag Scanning for jobs in: $projectRoot"

    # Import PSWebHost_Jobs module if available
    $modulePath = Join-Path $projectRoot "modules\PSWebHost_Jobs\PSWebHost_Jobs.psd1"
    $moduleLoaded = $false
    if (Test-Path $modulePath) {
        try {
            Import-Module $modulePath -DisableNameChecking -Force -ErrorAction Stop
            $moduleLoaded = $true
            Write-Verbose "$MyTag Imported PSWebHost_Jobs module"
        }
        catch {
            Write-Warning "$MyTag Failed to import PSWebHost_Jobs module: $_"
        }
    }

    # Get jobs using module if available, otherwise scan filesystem
    $jobs = @()

    if ($moduleLoaded -and (Get-Command Get-PSWebHostJobCatalog -ErrorAction SilentlyContinue)) {
        # Use module to get catalog
        Write-Verbose "$MyTag Using PSWebHost_Jobs module to get catalog"
        $catalog = Get-PSWebHostJobCatalog -ProjectRoot $projectRoot

        foreach ($jobKey in $catalog.Keys) {
            $jobInfo = $catalog[$jobKey]

            # Filter by app if specified
            if ($AppName -and $jobInfo.AppName -ne $AppName) {
                continue
            }

            $jobs += [PSCustomObject]@{
                JobID = $jobInfo.JobID
                AppName = $jobInfo.AppName
                JobName = $jobInfo.JobName
                DisplayName = $jobInfo.Name
                Description = $jobInfo.Description
                Schedule = $jobInfo.Metadata.default_schedule
                ScriptPath = $jobInfo.ScriptPath
                JobDirectory = $jobInfo.JobDirectory
                RolesStart = ($jobInfo.Metadata.roles_start -join ', ')
                RolesStop = ($jobInfo.Metadata.roles_stop -join ', ')
                RolesRestart = ($jobInfo.Metadata.roles_restart -join ', ')
                LastScanned = $jobInfo.LastScanned
                HasInitScript = (Test-Path (Join-Path $jobInfo.JobDirectory "init-job.ps1"))
                TemplateVariables = if ($jobInfo.Metadata.template_variables) {
                    ($jobInfo.Metadata.template_variables.PSObject.Properties.Name -join ', ')
                } else {
                    ''
                }
            }
        }
    }
    else {
        # Scan filesystem directly
        Write-Verbose "$MyTag Scanning filesystem directly (module not available)"
        $appsDir = Join-Path $projectRoot "apps"

        if (-not (Test-Path $appsDir)) {
            Write-Warning "$MyTag Apps directory not found: $appsDir"
            return
        }

        $appDirs = Get-ChildItem -Path $appsDir -Directory

        foreach ($app in $appDirs) {
            # Filter by app if specified
            if ($AppName -and $app.Name -ne $AppName) {
                continue
            }

            $jobsDir = Join-Path $app.FullName "jobs"
            if (-not (Test-Path $jobsDir)) {
                continue
            }

            $jobDirs = Get-ChildItem -Path $jobsDir -Directory

            foreach ($jobDir in $jobDirs) {
                $jobJsonPath = Join-Path $jobDir.FullName "job.json"

                if (-not (Test-Path $jobJsonPath)) {
                    Write-Warning "$MyTag Missing job.json in: $($jobDir.FullName)"
                    continue
                }

                try {
                    $jobJson = Get-Content -Path $jobJsonPath -Raw | ConvertFrom-Json

                    $jobs += [PSCustomObject]@{
                        JobID = "$($app.Name)/$($jobDir.Name)"
                        AppName = $app.Name
                        JobName = $jobDir.Name
                        DisplayName = $jobJson.Name
                        Description = $jobJson.Description
                        Schedule = $jobJson.default_schedule
                        ScriptPath = Join-Path $jobDir.FullName $jobJson.ScriptRelativePath
                        JobDirectory = $jobDir.FullName
                        RolesStart = ($jobJson.roles_start -join ', ')
                        RolesStop = ($jobJson.roles_stop -join ', ')
                        RolesRestart = ($jobJson.roles_restart -join ', ')
                        LastScanned = Get-Date
                        HasInitScript = (Test-Path (Join-Path $jobDir.FullName "init-job.ps1"))
                        TemplateVariables = if ($jobJson.template_variables) {
                            ($jobJson.template_variables.PSObject.Properties.Name -join ', ')
                        } else {
                            ''
                        }
                    }
                }
                catch {
                    Write-Warning "$MyTag Failed to load job from $jobJsonPath : $_"
                }
            }
        }
    }

    # Sort jobs
    $jobs = $jobs | Sort-Object AppName, JobName

    # Output based on format
    switch ($Format) {
        'Table' {
            Write-Host ""
            Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "  Available Jobs" -ForegroundColor Cyan
            Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host ""

            if ($jobs.Count -eq 0) {
                Write-Host "  No jobs found" -ForegroundColor Yellow
                Write-Host ""
                return
            }

            $jobs | Format-Table `
                @{Label='JobID'; Expression={$_.JobID}; Width=35}, `
                @{Label='Display Name'; Expression={$_.DisplayName}; Width=30}, `
                @{Label='Schedule'; Expression={$_.Schedule}; Width=15}, `
                @{Label='Init'; Expression={if($_.HasInitScript){'✓'}else{''}}; Width=4} `
                -AutoSize

            Write-Host ""
            Write-Host "Found $($jobs.Count) job(s)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Use -Format List for detailed information" -ForegroundColor DarkGray
            Write-Host "Use -Format Grid for interactive selection" -ForegroundColor DarkGray
            Write-Host ""
        }

        'List' {
            Write-Host ""
            Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "  Available Jobs (Detailed)" -ForegroundColor Cyan
            Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host ""

            if ($jobs.Count -eq 0) {
                Write-Host "  No jobs found" -ForegroundColor Yellow
                Write-Host ""
                return
            }

            foreach ($job in $jobs) {
                Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                Write-Host "JobID:              " -NoNewline -ForegroundColor Yellow
                Write-Host $job.JobID -ForegroundColor White
                Write-Host "Display Name:       " -NoNewline -ForegroundColor Gray
                Write-Host $job.DisplayName -ForegroundColor White
                Write-Host "Description:        " -NoNewline -ForegroundColor Gray
                Write-Host $job.Description -ForegroundColor White
                Write-Host "App:                " -NoNewline -ForegroundColor Gray
                Write-Host $job.AppName -ForegroundColor White
                Write-Host "Job Name:           " -NoNewline -ForegroundColor Gray
                Write-Host $job.JobName -ForegroundColor White
                Write-Host "Schedule:           " -NoNewline -ForegroundColor Gray
                Write-Host $job.Schedule -ForegroundColor White
                Write-Host "Job Directory:      " -NoNewline -ForegroundColor Gray
                Write-Host $job.JobDirectory -ForegroundColor DarkGray
                Write-Host "Script Path:        " -NoNewline -ForegroundColor Gray
                Write-Host $job.ScriptPath -ForegroundColor DarkGray
                Write-Host "Has Init Script:    " -NoNewline -ForegroundColor Gray
                Write-Host $job.HasInitScript -ForegroundColor White
                if ($job.TemplateVariables) {
                    Write-Host "Template Variables: " -NoNewline -ForegroundColor Gray
                    Write-Host $job.TemplateVariables -ForegroundColor Cyan
                }
                Write-Host "Roles (Start):      " -NoNewline -ForegroundColor Gray
                Write-Host $job.RolesStart -ForegroundColor Green
                Write-Host "Roles (Stop):       " -NoNewline -ForegroundColor Gray
                Write-Host $job.RolesStop -ForegroundColor Red
                Write-Host "Roles (Restart):    " -NoNewline -ForegroundColor Gray
                Write-Host $job.RolesRestart -ForegroundColor Yellow
                Write-Host ""
            }

            Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
            Write-Host "Found $($jobs.Count) job(s)" -ForegroundColor Gray
            Write-Host ""
        }

        'Json' {
            $jobs | ConvertTo-Json -Depth 10
            return
        }

        'Grid' {
            if ($jobs.Count -eq 0) {
                Write-Host "No jobs found" -ForegroundColor Yellow
                return
            }

            $selected = $jobs | Out-GridView -Title "Available Jobs - Select to view details" -PassThru

            if ($selected) {
                Write-Host ""
                Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
                Write-Host "  Selected Job Details" -ForegroundColor Cyan
                Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "JobID:              " -NoNewline -ForegroundColor Yellow
                Write-Host $selected.JobID -ForegroundColor White
                Write-Host "Display Name:       " -NoNewline -ForegroundColor Gray
                Write-Host $selected.DisplayName -ForegroundColor White
                Write-Host "Description:        " -NoNewline -ForegroundColor Gray
                Write-Host $selected.Description -ForegroundColor White
                Write-Host ""
                Write-Host "Commands:" -ForegroundColor Cyan
                Write-Host "  Test:    " -NoNewline -ForegroundColor Gray
                Write-Host ".\system\utility\TaskManagement_AppJobFolder_Test.ps1 -AppName '$($selected.AppName)' -JobName '$($selected.JobName)'" -ForegroundColor DarkGray
                Write-Host "  Start:   " -NoNewline -ForegroundColor Gray
                Write-Host ".\system\utility\TaskManagement_AppJobFolder_Start.ps1 -AppName '$($selected.AppName)' -JobName '$($selected.JobName)'" -ForegroundColor DarkGray
                Write-Host "  Stop:    " -NoNewline -ForegroundColor Gray
                Write-Host ".\system\utility\TaskManagement_AppJobFolder_Stop.ps1 -AppName '$($selected.AppName)' -JobName '$($selected.JobName)'" -ForegroundColor DarkGray
                Write-Host "  Restart: " -NoNewline -ForegroundColor Gray
                Write-Host ".\system\utility\TaskManagement_AppJobFolder_Restart.ps1 -AppName '$($selected.AppName)' -JobName '$($selected.JobName)'" -ForegroundColor DarkGray
                Write-Host ""
            }
        }
    }

    # Return jobs for scripting
    return $jobs
}
catch {
    Write-Error "$MyTag $_"
    throw
}
