#Requires -Version 7

<#
.SYNOPSIS
    Job Command Queue Helper Module

.DESCRIPTION
    Provides file-based command queue for API endpoints (running in runspaces)
    to communicate with main_loop.ps1 (running in main process)

.NOTES
    API endpoints write commands to files in the queue directory
    main_loop.ps1 reads and processes these commands with access to $Global:PSWebServer.Jobs
#>

function Get-JobCommandQueuePath {
    <#
    .SYNOPSIS
        Gets the job command queue directory path
    #>
    [CmdletBinding()]
    param()

    $dataRoot = if ($Global:PSWebServer.DataPath) {
        $Global:PSWebServer.DataPath
    } else {
        Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"
    }

    $queuePath = Join-Path $dataRoot "apps\WebHostTaskManagement\JobCommandQueue"

    if (-not (Test-Path $queuePath)) {
        New-Item -Path $queuePath -ItemType Directory -Force | Out-Null
    }

    return $queuePath
}

function Submit-JobCommand {
    <#
    .SYNOPSIS
        Submits a job command to the queue for main_loop.ps1 to process

    .PARAMETER Command
        Command type: 'start', 'stop', 'restart', 'status'

    .PARAMETER JobID
        Job identifier (AppName/JobName)

    .PARAMETER UserID
        User ID submitting the command

    .PARAMETER SessionID
        Optional session ID

    .PARAMETER Variables
        Optional hashtable of template variables

    .PARAMETER Roles
        User roles for permission checking
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('start', 'stop', 'restart', 'status')]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$JobID,

        [Parameter(Mandatory)]
        [string]$UserID,

        [string]$SessionID,

        [hashtable]$Variables = @{},

        [string[]]$Roles = @()
    )

    $queuePath = Get-JobCommandQueuePath

    # Generate unique command ID
    $commandID = [guid]::NewGuid().ToString()

    # Create command object
    $commandObj = @{
        CommandID = $commandID
        Command = $Command
        JobID = $JobID
        UserID = $UserID
        SessionID = $SessionID
        Variables = $Variables
        Roles = $Roles
        SubmittedAt = (Get-Date).ToString('o')
        Status = 'Pending'
    }

    # Write to queue file
    $commandFile = Join-Path $queuePath "$commandID.json"
    $commandObj | ConvertTo-Json -Depth 10 | Set-Content -Path $commandFile -Encoding UTF8

    Write-Verbose "[JobCommandQueue] Submitted command $commandID ($Command for $JobID)"

    return $commandObj
}

function Get-JobCommandStatus {
    <#
    .SYNOPSIS
        Gets the status of a submitted command

    .PARAMETER CommandID
        Command ID to check
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandID
    )

    $queuePath = Get-JobCommandQueuePath

    # Check if command file still exists (pending)
    $commandFile = Join-Path $queuePath "$CommandID.json"
    if (Test-Path $commandFile) {
        $command = Get-Content -Path $commandFile -Raw | ConvertFrom-Json
        return @{
            Status = $command.Status
            Command = $command.Command
            JobID = $command.JobID
            SubmittedAt = $command.SubmittedAt
        }
    }

    # Check results directory
    $resultsPath = Join-Path (Split-Path $queuePath) "JobCommandResults"
    $resultFile = Join-Path $resultsPath "$CommandID.json"

    if (Test-Path $resultFile) {
        $result = Get-Content -Path $resultFile -Raw | ConvertFrom-Json
        return @{
            Status = $result.Status
            Command = $result.Command
            JobID = $result.JobID
            SubmittedAt = $result.SubmittedAt
            ProcessedAt = $result.ProcessedAt
            ExecutionID = $result.ExecutionID
            Error = $result.Error
        }
    }

    return $null
}

function Get-JobStatus {
    <#
    .SYNOPSIS
        Gets the status of a running or completed job

    .PARAMETER ExecutionID
        Execution ID of the job

    .PARAMETER UserID
        User ID for permission checking
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExecutionID,

        [Parameter(Mandatory)]
        [string]$UserID
    )

    # Check running jobs status file
    $dataRoot = if ($Global:PSWebServer.DataPath) {
        $Global:PSWebServer.DataPath
    } else {
        Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"
    }

    $statusPath = Join-Path $dataRoot "apps\WebHostTaskManagement\JobStatus"
    $statusFile = Join-Path $statusPath "$ExecutionID.json"

    if (Test-Path $statusFile) {
        $status = Get-Content -Path $statusFile -Raw | ConvertFrom-Json

        # Check if user has permission to view this job
        if ($status.UserID -eq $UserID) {
            return @{
                ExecutionID = $status.ExecutionID
                JobID = $status.JobID
                Status = $status.Status
                StartTime = $status.StartTime
                EndTime = $status.EndTime
                UserID = $status.UserID
            }
        }
    }

    return $null
}

Export-ModuleMember -Function @(
    'Submit-JobCommand',
    'Get-JobCommandStatus',
    'Get-JobStatus'
)
