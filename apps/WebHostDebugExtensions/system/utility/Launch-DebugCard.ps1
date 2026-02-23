<#
.SYNOPSIS
    Launches a card in the browser via the debug command queue

.DESCRIPTION
    Enqueues an openCard command to launch a card by URL in the target browser session.
    Supports session-specific targeting and waits for command completion.

.PARAMETER Url
    The card URL to launch (e.g., "/apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer")

.PARAMETER Title
    Optional title for the card (defaults to "Debug Card")

.PARAMETER SessionID
    Target session ID. Defaults to "all" to target all sessions.

.PARAMETER TimeoutSeconds
    Maximum time to wait for command completion (default: 10 seconds)

.PARAMETER Wait
    If specified, waits for command to complete and returns result

.EXAMPLE
    Launch-DebugCard -Url "/apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer" -Title "File Explorer"

.EXAMPLE
    Launch-DebugCard -Url "/apps/WebHostMetrics/api/v1/ui/elements/server-heatmap" -SessionID "abc123" -Wait

.OUTPUTS
    Returns command ID when launched, or result object if -Wait is specified
#>
[CmdletBinding()]
param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Url,

        [Parameter(Mandatory = $false)]
        [string]$Title = "Debug Card",

        [Parameter(Mandatory = $false)]
        [string]$SessionID = "all",

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 10,

        [Parameter(Mandatory = $false)]
        [switch]$Wait
    )

    $MyTag = '[Launch-DebugCard]'

    try {
        # Validate URL format
        if ($Url -notmatch '^/') {
            throw "URL must start with '/' (e.g., '/apps/...')"
        }

        Write-Verbose "$MyTag Launching card: $Title at $Url"

        # Build parameters for openCard command
        $commandParams = @{
            url = $Url
            title = $Title
        }

        # Enqueue the command
        $enqueueScript = Join-Path $PSScriptRoot "Debug_Client_Command_Enqueue.ps1"
        $result = & $enqueueScript `
            -Command "openCard" `
            -Type predefined `
            -Params $commandParams `
            -SessionID $SessionID

        if (-not $result.Success) {
            throw "Failed to enqueue command: $($result.Message)"
        }

        $commandId = $result.CommandID
        Write-Verbose "$MyTag Command enqueued: $commandId"

        if ($Wait) {
            Write-Verbose "$MyTag Waiting for command completion (timeout: ${TimeoutSeconds}s)..."

            $startTime = Get-Date
            $completed = $false
            $commandResult = $null

            while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
                Start-Sleep -Milliseconds 500

                # Poll history endpoint via HTTP
                try {
                    $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET

                    $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $commandId } | Select-Object -First 1

                    if ($historyEntry) {
                        $completed = $true
                        $commandResult = $historyEntry
                        break
                    }
                } catch {
                    Write-Verbose "$MyTag Error polling history: $_"
                }
            }

            if (-not $completed) {
                Write-Warning "$MyTag Command did not complete within ${TimeoutSeconds}s"
                return @{
                    Success = $false
                    CommandID = $commandId
                    Message = "Timeout waiting for command completion"
                }
            }

            Write-Verbose "$MyTag Command completed successfully"
            return @{
                Success = $true
                CommandID = $commandId
                Result = $commandResult.Result
                Timestamp = $commandResult.CompletedTime
            }

        } else {
            # Return immediately with command ID
            return @{
                Success = $true
                CommandID = $commandId
                SessionID = $SessionID
                Url = $Url
                Title = $Title
            }
        }

} catch {
    Write-Error "$MyTag Error launching card: $_"
    return @{
        Success = $false
        Error = $_.Exception.Message
    }
}
