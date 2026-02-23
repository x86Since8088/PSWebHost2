#Requires -Version 7

<#
.SYNOPSIS
    Enqueues a client-side debug command via file-based queue

.DESCRIPTION
    Writes command to outbox folder for browser pickup via polling endpoint.
    Simple file-based approach - no HTTP calls or authentication needed.

.PARAMETER Command
    JavaScript code to execute or predefined command name

.PARAMETER SessionID
    Target session ID (or "all" for broadcast to all sessions)
    Default: "all"

.PARAMETER Type
    Command type: eval|predefined|dom|network|jscommand

.PARAMETER Params
    Parameters for predefined commands (hashtable)

.PARAMETER DataRoot
    Root data directory (default: .\PsWebHost_Data)

.PARAMETER Wait
    Wait for command execution to complete and return results

.PARAMETER TimeoutSeconds
    Maximum time to wait for command completion when using -Wait (default: 30)

.EXAMPLE
    .\Debug_Client_Command_Enqueue.ps1 -Command "console.log('Hello!')" -Type eval

.EXAMPLE
    .\Debug_Client_Command_Enqueue.ps1 -Command "dumpState" -Type predefined -Wait

.EXAMPLE
    .\Debug_Client_Command_Enqueue.ps1 -Command "openCard" -Type predefined -Params @{url="/test"; title="Test"} -SessionID "abc123"

.OUTPUTS
    Hashtable with Success, CommandID, OutboxPath, or Result (if -Wait)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Command,

    [Parameter(Position=1)]
    [string]$SessionID = "all",

    [Parameter(Position=2)]
    [ValidateSet('eval', 'predefined', 'dom', 'network', 'jscommand')]
    [string]$Type = "eval",

    [Parameter(Position=3)]
    [hashtable]$Params = @{},

    [Parameter()]
    [string]$DataRoot = ".\PsWebHost_Data",

    [Parameter()]
    [switch]$Wait,

    [Parameter()]
    [int]$TimeoutSeconds = 30
)

$MyTag = '[Debug-ClientCommand]'

try {
    # Resolve data root path
    if (-not [System.IO.Path]::IsPathRooted($DataRoot)) {
        $DataRoot = Join-Path $PSScriptRoot "..\..\..\..\$DataRoot"
        $DataRoot = [System.IO.Path]::GetFullPath($DataRoot)
    }

    # Ensure outbox directory exists
    $outboxRoot = Join-Path $DataRoot "apps\WebHostDebugExtensions\outbox"
    $sessionOutbox = Join-Path $outboxRoot $SessionID

    if (-not (Test-Path $sessionOutbox)) {
        New-Item -Path $sessionOutbox -ItemType Directory -Force | Out-Null
        Write-Verbose "$MyTag Created outbox directory: $sessionOutbox"
    }

    # Generate command ID
    $commandID = [guid]::NewGuid().ToString()

    # Build command object
    $commandObj = @{
        CommandID = $commandID
        SessionID = $SessionID
        Type = $Type
        Command = $Command
        Params = $Params
        Status = 'pending'
        EnqueuedAt = (Get-Date).ToString('o')
        TimeoutAt = (Get-Date).AddSeconds(60).ToString('o')
    }

    # Write to outbox
    $outboxFile = Join-Path $sessionOutbox "$commandID.json"
    $commandObj | ConvertTo-Json -Depth 10 | Out-File -FilePath $outboxFile -Encoding UTF8 -Force

    Write-Verbose "$MyTag Command written to outbox: $outboxFile"
    Write-Verbose "$MyTag   Type: $Type"
    Write-Verbose "$MyTag   SessionID: $SessionID"
    Write-Verbose "$MyTag   CommandID: $commandID"

    # If not waiting, return immediately
    if (-not $Wait) {
        return @{
            Success = $true
            CommandID = $commandID
            SessionID = $SessionID
            OutboxPath = $outboxFile
        }
    }

    # Wait for result in inbox
    Write-Verbose "$MyTag Waiting for command completion (timeout: ${TimeoutSeconds}s)..."

    $inboxRoot = Join-Path $DataRoot "apps\WebHostDebugExtensions\inbox"

    $startTime = Get-Date
    $completed = $false
    $received = $false
    $result = $null

    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Milliseconds 500

        # Check for result file in inbox - search all locations since we don't know which session will respond
        $inboxFile = Get-ChildItem -Path $inboxRoot -Filter "$commandID.json" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($inboxFile) {
            try {
                $resultContent = Get-Content -Path $inboxFile.FullName -Raw -Encoding UTF8
                $result = $resultContent | ConvertFrom-Json

                # Check status
                if ($result.Status -eq 'received' -and -not $received) {
                    Write-Verbose "$MyTag Command received by browser, awaiting execution..."
                    $received = $true
                    # Don't break - wait for completion
                }
                elseif ($result.Status -eq 'completed' -or $result.Status -eq 'failed') {
                    Write-Verbose "$MyTag Command execution complete: Status=$($result.Status)"

                    # Clean up inbox file
                    Remove-Item -Path $inboxFile.FullName -Force -ErrorAction SilentlyContinue
                    Write-Verbose "$MyTag Cleaned up inbox file"

                    $completed = $true
                    break
                }
            } catch {
                Write-Verbose "$MyTag Error reading inbox file: $_"
            }
        }
    }

    if (-not $completed) {
        Write-Warning "$MyTag Command did not complete within ${TimeoutSeconds}s"

        # Clean up outbox file if it still exists (never picked up)
        if (Test-Path $outboxFile) {
            Remove-Item -Path $outboxFile -Force -ErrorAction SilentlyContinue
        }

        return @{
            Success = $false
            CommandID = $commandID
            Message = "Timeout waiting for command completion"
            TimeoutSeconds = $TimeoutSeconds
        }
    }

    Write-Verbose "$MyTag Command completed: Status=$($result.Status)"

    return @{
        Success = ($result.Status -eq 'completed')
        CommandID = $commandID
        Status = $result.Status
        Result = $result.Result
        Error = $result.Error
        ExecutionTimeMs = $result.ExecutionTimeMs
        CompletedAt = $result.CompletedAt
    }

} catch {
    Write-Error "$MyTag Failed to enqueue command: $_"
    return @{
        Success = $false
        Error = $_.Exception.Message
    }
}
